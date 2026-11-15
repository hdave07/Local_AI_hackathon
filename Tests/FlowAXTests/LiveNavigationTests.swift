import AppKit
import CoreGraphics
@testable import FlowAX
import FlowCore
import FlowWindow
import Foundation
import Testing

/// Live integration tests against REAL apps through the real Accessibility API.
/// Opt in: `swift build --product flow-nav-fixture && FLOW_LIVE_AX=1 swift test --filter FlowAXTests`.
/// Requires Accessibility permission for the test runner's terminal/IDE.
/// The fixture is a separate AppKit process (Sources/FlowNavFixture); Calculator and
/// System Settings are stock macOS apps used read-only (Calculator's display is reset).
@MainActor
@Suite("Live UI navigation", .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"), .serialized)
struct LiveNavigationTests {
    // MARK: Fixture

    final class Fixture {
        let process: Process
        let pid: pid_t
        init(process: Process) {
            self.process = process
            pid = process.processIdentifier
        }
        deinit { process.terminate() }
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/debug/flow-nav-fixture")
    }

    func launchFixture(_ backend: AXUIBackend) async throws -> Fixture {
        try #require(AccessibilityPermission.isTrusted, "grant Accessibility to the test runner's terminal/IDE")
        try #require(FileManager.default.isExecutableFile(atPath: Self.fixtureURL.path),
                     "build it first: swift build --product flow-nav-fixture")
        let process = Process()
        process.executableURL = Self.fixtureURL
        try process.run()
        let fixture = Fixture(process: process)
        for _ in 0..<60 {
            if let app = try? backend.resolveApp(.pid(fixture.pid)),
                let s = try? backend.observe(app, limits: SnapshotLimits()), s.elements.contains(where: { $0.label == "Save" })
            {
                return fixture
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NavParseError(message: "fixture window never became accessible")
    }

    func makeNav(bringToFront: Bool = false, overlay: OverlayPresenting? = nil) -> (UINavigator, AXUIBackend) {
        let backend = AXUIBackend(frontmost: { nil })
        var c = UINavigator.Configuration()
        c.bringTargetToFront = bringToFront
        return (UINavigator(backend: backend, overlay: overlay, configuration: c), backend)
    }

    func status(_ backend: AXUIBackend, _ pid: pid_t) throws -> String? {
        let s = try backend.observe(backend.resolveApp(.pid(pid)), limits: SnapshotLimits())
        return s.elements.first { $0.identifier == "status" }?.label
    }

    func log(_ r: NavigationResult) { print("LIVE-NAV\n\(r.report)") }

    // MARK: Acceptance tests

    @Test func locateAndActivateNamedControl() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        let r = await nav.perform(.click(.parse("the Save button"), .pid(fx.pid)))
        log(r)
        #expect(r.status == .completed)
        #expect(try status(backend, fx.pid) == "Status: Save pressed")
    }

    @Test func focusTextField() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        let r = await nav.perform(.focus(.parse("the search field"), .pid(fx.pid)))
        log(r)
        #expect(r.status == .completed)
        // Independent re-read: which element does the app report as focused?
        let s = try backend.snapshot(of: backend.resolveApp(.pid(fx.pid)), limits: SnapshotLimits())
        let search = try #require(s.elements.first { $0.identifier == "search" })
        #expect(backend.isFocusedElement(search.id, in: s.app))
    }

    @Test func scrollSupportedView() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        let down = await nav.perform(.scroll(.parse("results list"), .down, .pid(fx.pid)))
        log(down)
        #expect(down.status == .completed)
        let bottom = await nav.perform(.scroll(nil, .bottom, .pid(fx.pid)))
        log(bottom)
        #expect(bottom.status == .completed)
        let limit = await nav.perform(.scroll(nil, .down, .pid(fx.pid)))
        #expect(limit.error == .atScrollLimit("bottom"))
        let top = await nav.perform(.scroll(nil, .top, .pid(fx.pid)))
        #expect(top.status == .completed)
    }

    @Test func showNumberedTargetsAndSelectOne() async throws {
        let overlay = RecordingOverlay()
        let (nav, backend) = makeNav(overlay: overlay)
        let fx = try await launchFixture(backend)
        let shown = await nav.perform(.showNumbers(.parse("reply"), .pid(fx.pid)))
        log(shown)
        let options = try #require(shown.clarification?.options)
        // Numbers map to the real, currently available elements, in reading order.
        #expect(options.map(\.element.identifier) == ["replyA", "replyB"])
        #expect(overlay.isVisible)
        let chosen = await nav.perform(.choose(2))
        log(chosen)
        #expect(chosen.status == .completed)
        #expect(try status(backend, fx.pid) == "Status: Reply B pressed")
        #expect(!overlay.isVisible)
    }

    @Test func indistinguishableTargetsReturnClarificationWithoutClicking() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        let r = await nav.perform(.click(.parse("reply"), .pid(fx.pid)))
        log(r)
        #expect(r.status == .needsClarification)
        #expect(r.clarification?.options.count == 2)
        #expect(try status(backend, fx.pid) == "Status: ready", "nothing was pressed")
    }

    @Test func staleNumbersAreRefused() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        _ = await nav.perform(.showNumbers(.parse("volatile"), .pid(fx.pid)))
        // Change the layout with a separate navigator so the numbered set stays active.
        let (other, _) = makeNav()
        #expect(await other.perform(.click(.parse("shift volatile"), .pid(fx.pid))).status == .completed)
        let r = await nav.perform(.choose(1))
        log(r)
        #expect(r.error == .staleNumbers)
        #expect(try status(backend, fx.pid) == "Status: ready", "Volatile was not pressed")
    }

    @Test func changedOrRemovedTargetIsRefused() async throws {
        let (nav, backend) = makeNav()
        let fx = try await launchFixture(backend)
        let app = try backend.resolveApp(.pid(fx.pid))

        var s = try backend.snapshot(of: app, limits: SnapshotLimits())
        var volatile = try #require(s.elements.first { $0.label == "Volatile" })
        #expect(await nav.perform(.click(.parse("remove volatile"), .pid(fx.pid))).status == .completed)
        let gone = await nav.perform(.click, on: volatile, in: app)
        log(gone)
        #expect(gone.error == .targetGone)

        #expect(await nav.perform(.click(.parse("restore volatile"), .pid(fx.pid))).status == .completed)
        s = try backend.snapshot(of: app, limits: SnapshotLimits())
        volatile = try #require(s.elements.first { $0.label == "Volatile" })
        #expect(await nav.perform(.click(.parse("rename volatile"), .pid(fx.pid))).status == .completed)
        let renamed = await nav.perform(.click, on: volatile, in: app)
        log(renamed)
        guard case .targetChanged = renamed.error else { Issue.record("got \(String(describing: renamed.error))"); return }

        #expect(await nav.perform(.click(.parse("restore volatile"), .pid(fx.pid))).status == .completed)
        s = try backend.snapshot(of: app, limits: SnapshotLimits())
        volatile = try #require(s.elements.first { $0.label == "Volatile" })
        #expect(await nav.perform(.click(.parse("shift volatile"), .pid(fx.pid))).status == .completed)
        let moved = await nav.perform(.click, on: volatile, in: app)
        log(moved)
        guard case .targetChanged = moved.error else { Issue.record("got \(String(describing: moved.error))"); return }
        #expect(try status(backend, fx.pid) != "Status: Volatile pressed")
    }

    @Test func calculatorNamedControlsInStockApp() async throws {
        try #require(AccessibilityPermission.isTrusted)
        let url = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator"))
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        let (nav, backend) = makeNav(bringToFront: true)
        let scope = AppScope.named("Calculator")
        // A cold-launched Calculator answers AX with "cannot complete" until its window exists.
        for _ in 0..<50 {
            if let app = try? backend.resolveApp(scope), (try? backend.observe(app, limits: SnapshotLimits())) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Setup: All Clear is `unverified` when the display already shows 0 (nothing visibly changes).
        let clear = await nav.perform(.click(.parse("all clear"), scope))
        #expect(clear.status == .completed || clear.status == .unverified)
        for key in ["seven", "plus", "the 3 button", "equals"] {
            let r = await nav.perform(.click(.parse(key), scope))
            log(r)
            #expect(r.status == .completed, "\(key)")
        }
        let s = try backend.observe(backend.resolveApp(scope), limits: SnapshotLimits())
        let display = s.elements.filter { $0.kind == .staticText && $0.isVisible }.map(\.label)
        #expect(display.contains("10"), "display texts: \(display)")
        _ = await nav.perform(.click(.parse("all clear"), scope))
    }

    @Test func systemSettingsSidebarScrollsReadOnly() async throws {
        try #require(AccessibilityPermission.isTrusted)
        let url = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"))
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        try await Task.sleep(for: .seconds(1))
        let (nav, _) = makeNav(bringToFront: true)
        let scope = AppScope.named("System Settings")
        let bottom = await nav.perform(.scroll(.parse("the sidebar"), .bottom, scope))
        log(bottom)
        #expect(bottom.status == .completed || bottom.error == .atScrollLimit("bottom"))
        let top = await nav.perform(.scroll(.parse("the sidebar"), .top, scope))
        log(top)
        #expect(top.status == .completed)
    }
}
