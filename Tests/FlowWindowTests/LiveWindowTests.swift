import CoreGraphics
import FlowCore
import FlowWindow
import Foundation
import Testing

/// Milestone integration test against the REAL Notes window via Accessibility.
/// Opt in: `FLOW_LIVE_AX=1 swift test --filter LiveWindowTests`.
/// Requires Accessibility permission for the process running the tests (or its parent terminal/IDE).
@MainActor
@Suite(
    "Live macOS window control",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"),
    .serialized
)
struct LiveWindowTests {
    @Test func milestoneActivateMoveVerifyUndoNotes() async throws {
        try #require(AccessibilityPermission.isTrusted, "grant Accessibility to the test runner's terminal/IDE")
        let backend = AXWindowBackend()
        let controller = WindowController(backend: backend)

        func run(_ text: String) async throws -> WindowActionResult {
            guard case .window(let command) = try WindowCommandParser.parse(text) else {
                throw CommandParseError(message: "not a window command")
            }
            let result = await controller.perform(command)
            print("LIVE-AX > \(text)\n\(result.report)")
            return result
        }

        // 1. Activate Notes.
        let activate = try await run("activate notes")
        try #require(activate.status == .completed)

        let notes = try #require(backend.runningApp(bundleID: KnownApp.notes.bundleIdentifier))
        let screen = try #require(backend.usableScreenFrame())
        let windowsBefore = try controller.listWindows(.notes).filter { !$0.isMinimized }
        print("LIVE-AX screen \(screen.compactDescription); Notes windows: \(windowsBefore.map { "\($0.displayName) \($0.frame.compactDescription)" })")

        // 2. Move its window to the left half.
        let move = try await run("move notes left_half")
        let target = try #require(move.targets.first)
        let originalFrame = try #require(move.before.first)

        // Safety net: put the window back even if an assertion below fails.
        defer {
            if let now = try? backend.state(of: target.id), !WindowGeometry.approximatelyEqual(now.frame, originalFrame) {
                try? backend.setPosition(target.id, originalFrame.origin)
                try? backend.setSize(target.id, originalFrame.size)
                try? backend.setPosition(target.id, originalFrame.origin)
            }
        }

        #expect(move.status == .completed)
        let expectedLeft = WindowGeometry.targetFrame(for: .leftHalf, current: originalFrame, screen: screen)
        #expect(move.expected == [expectedLeft])

        // 3. Verify the final position by re-reading the real window, then the window server.
        let reread = try backend.state(of: target.id)
        #expect(WindowGeometry.approximatelyEqual(reread.frame, expectedLeft), "AX frame \(reread.frame.compactDescription)")
        let serverAgrees = await eventually {
            backend.windowServerFrames(pid: notes.pid).contains { WindowGeometry.approximatelyEqual($0, expectedLeft) }
        }
        #expect(serverAgrees, "CGWindowList bounds: \(backend.windowServerFrames(pid: notes.pid).map(\.compactDescription))")

        // 4. Undo and restore the original position.
        let undo = try await run("undo")
        #expect(undo.status == .completed)
        let restored = try backend.state(of: target.id)
        #expect(WindowGeometry.approximatelyEqual(restored.frame, originalFrame), "restored \(restored.frame.compactDescription)")
        let serverRestored = await eventually {
            backend.windowServerFrames(pid: notes.pid).contains { WindowGeometry.approximatelyEqual($0, originalFrame) }
        }
        #expect(serverRestored, "CGWindowList bounds: \(backend.windowServerFrames(pid: notes.pid).map(\.compactDescription))")
        print("LIVE-AX original \(originalFrame.compactDescription) → left \(reread.frame.compactDescription) → restored \(restored.frame.compactDescription)")
    }

    @Test func minimizeAndRestoreNotes() async throws {
        try #require(AccessibilityPermission.isTrusted)
        let controller = WindowController(backend: AXWindowBackend())
        try #require(await controller.perform(.activate(.notes)).status == .completed)
        let minimize = await controller.perform(.minimize(.app(.notes)))
        print("LIVE-AX\n\(minimize.report)")
        #expect(minimize.status == .completed)
        let restore = await controller.perform(.restore(.app(.notes)))
        print("LIVE-AX\n\(restore.report)")
        #expect(restore.status == .completed)
        #expect(restore.observed.first?.isMinimized == false)
    }

    @Test func unsupportedAppIsRejectedBeforeAnyAX() throws {
        #expect(throws: CommandParseError.self) { try WindowCommandParser.parse("activate terminal") }
    }

    private func eventually(_ timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
}
