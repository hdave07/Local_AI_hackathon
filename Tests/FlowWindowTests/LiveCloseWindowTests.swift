import AppKit
import FlowCore
@testable import FlowWindow
import Foundation
import Testing

/// Live close through the real Accessibility close button, on Flow's own test fixture app
/// (never on the user's windows). Opt in: `swift build --product flow-nav-fixture && FLOW_LIVE_AX=1 swift test --filter LiveCloseWindowTests`.
@MainActor
@Suite("Live: close window", .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"), .serialized)
struct LiveCloseWindowTests {
    @Test func closesTheFrontmostFixtureWindowThroughItsCloseButton() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/debug/flow-nav-fixture")
        try #require(FileManager.default.isExecutableFile(atPath: url.path), "swift build --product flow-nav-fixture")
        let process = Process()
        process.executableURL = url
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let backend = AXWindowBackend()
        let app = AppHandle(pid: process.processIdentifier, bundleID: "flow-nav-fixture", name: "Fixture")
        var window: WindowState?
        for _ in 0..<60 where window == nil {
            try await Task.sleep(for: .milliseconds(100))
            window = (try? backend.windows(of: app))?.first(where: \.isStandard)
        }
        let target = try #require(window, "the fixture never showed a window")
        // The real close button, pressed through Accessibility.
        try backend.close(target.id)
        var gone = false
        for _ in 0..<40 where !gone {
            try await Task.sleep(for: .milliseconds(50))
            if !process.isRunning { gone = true; break }  // the fixture quits after its last window closes
            if case .failure(let e) = Result(catching: { () throws(WindowError) in try backend.state(of: target.id) }), e == .windowGone { gone = true }
            if let ws = try? backend.windows(of: app), !ws.contains(where: { $0.id == target.id }) { gone = true }
        }
        #expect(gone, "the fixture window is still open")
        #expect(!backend.hasSheet(target.id))
    }
}
