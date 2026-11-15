import CoreGraphics
import FlowCore
@testable import FlowWindow
import Testing

private let frame = CGRect(x: 205, y: 151, width: 858, height: 647)

/// Closing windows (ADR 0011): verified, never quits the app, never answers "save changes?".
@MainActor
@Suite("WindowController: close")
struct CloseWindowTests {
    func controller(_ b: FakeWindowBackend) -> WindowController {
        var c = WindowController.Configuration()
        c.settleTimeout = .milliseconds(60)
        c.pollInterval = .milliseconds(5)
        return WindowController(backend: b, configuration: c)
    }

    @Test func closesTheWindowAndKeepsTheAppRunning() async {
        let b = FakeWindowBackend()
        let id = b.addWindow(.notes, "Groceries", frame)
        let r = await controller(b).perform(.close(.app(.notes)))
        #expect(r.status == .completed)
        #expect(b.windows[id] == nil)
        #expect(b.running[KnownApp.notes.bundleIdentifier] != nil, "the app is never quit")
        #expect(r.userMessage.contains("Notes is still open"))
        #expect(!controller(b).canUndo)
    }

    @Test func unsavedChangesSheetIsLeftForTheUser() async {
        let b = FakeWindowBackend()
        let id = b.addWindow(.notes, "Draft", frame)
        b.unsaved = [id]
        let r = await controller(b).perform(.close(.app(.notes)))
        #expect(r.status == .partiallyCompleted)
        #expect(r.userMessage.contains("asking whether to save"))
        #expect(b.windows[id] != nil, "nothing discarded")
        #expect(b.closeRequests == 1, "Flow pressed close once and answered nothing")
    }

    @Test func windowThatDoesNotCloseIsUnverified() async {
        let b = FakeWindowBackend()
        let id = b.addWindow(.notes, "Stubborn", frame)
        b.refusesClose = [id]
        let r = await controller(b).perform(.close(.app(.notes)))
        #expect(r.status == .unverified)
    }

    @Test func activeWindowIsTheFrontmostAppsFocusedWindow() async {
        let b = FakeWindowBackend()
        let notes = b.addWindow(.notes, "Groceries", frame)
        let ideas = b.addWindow(.notes, "Ideas", frame)
        b.front = b.running[KnownApp.notes.bundleIdentifier]
        b.focused[b.front!.pid] = ideas
        let r = await controller(b).perform(.close(.active))
        #expect(r.status == .completed)
        #expect(b.windows[ideas] == nil && b.windows[notes] != nil)
    }

    @Test func severalWindowsWithoutFocusAsksWhichOne() async {
        let b = FakeWindowBackend()
        b.addWindow(.notes, "Groceries", frame)
        b.addWindow(.notes, "Ideas", frame)
        let r = await controller(b).perform(.close(.app(.notes)))
        #expect(r.status == .failed)
        if case .ambiguousWindow = r.error {} else { Issue.record("expected ambiguity, got \(String(describing: r.error))") }
        #expect(b.closeRequests == 0)
    }

    @Test func appNotRunningOrNoWindow() async {
        let b = FakeWindowBackend()
        #expect(await controller(b).perform(.close(.app(.mail))).error == .appNotRunning("Mail"))
        b.launch(.mail)
        #expect(await controller(b).perform(.close(.app(.mail))).error == .noWindow("Mail"))
    }

    @Test func bridgedFromFlowActions() {
        #expect(WindowCommand(.closeWindow(.active)) == .close(.active))
        #expect(WindowCommand(.minimizeWindow(.app(.notes))) == .minimize(.app(.notes)))
        #expect(WindowCommand(.restoreWindow(.app(.notes))) == .restore(.app(.notes)))
        #expect(WindowCommand(.listWindows) == nil)
    }
}
