import Foundation

/// Runs an OSA (JavaScript for Automation) script out of process with one JSON argument.
/// Out of process so slow Mail queries never block Flow's main thread; the macOS
/// Automation consent is attributed to the responsible app (Flow.app, or the terminal).
public protocol ScriptRunning: Sendable {
    func run(javaScript: String, argument: String, timeout: Duration) async throws(MailError) -> Data
}

public struct OSAScriptRunner: ScriptRunning {
    public init() {}

    public func run(javaScript: String, argument: String, timeout: Duration) async throws(MailError) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // The argument is passed as argv, never spliced into the script text.
        process.arguments = ["-l", "JavaScript", "-e", javaScript, argument]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let exit = ExitWaiter()
        process.terminationHandler = { exit.finish($0.terminationStatus) }
        do {
            try process.run()
        } catch {
            throw .launchFailed
        }
        // Drain both pipes while the script runs so large bodies can't fill the pipe buffer.
        let outReader = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errReader = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if process.isRunning {
                exit.markTimedOut()
                process.terminate()
            }
        }
        let status = await exit.wait()
        timer.cancel()
        let out = await outReader.value
        let err = await errReader.value
        if exit.timedOut { throw .timedOut }
        guard status == 0 else { throw Self.mapError(String(decoding: err, as: UTF8.self)) }
        return out
    }

    /// Maps osascript stderr to a typed error, keeping only the numeric OSA code.
    static func mapError(_ stderr: String) -> MailError {
        let code = Self.errorCode(in: stderr)
        switch code {
        case -1743: return .automationDenied
        case -1744: return .automationNotDetermined
        case -600, -609: return .launchFailed
        case -1712: return .timedOut
        default: return .scriptFailure(code: code ?? 1)
        }
    }

    static func errorCode(in stderr: String) -> Int? {
        // osascript ends errors with "(-1743)".
        guard let open = stderr.lastIndex(of: "("), let close = stderr.lastIndex(of: ")"), open < close else { return nil }
        return Int(stderr[stderr.index(after: open)..<close])
    }
}

/// Waits for a process exit status; safe against the handler firing before `wait()`.
final class ExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?
    private(set) var timedOut = false

    func finish(_ value: Int32) {
        lock.lock()
        if let c = continuation {
            continuation = nil
            lock.unlock()
            c.resume(returning: value)
        } else {
            status = value
            lock.unlock()
        }
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { c in
            lock.lock()
            if let status {
                lock.unlock()
                c.resume(returning: status)
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }
}
