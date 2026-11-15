import CoreGraphics
import FlowCore
@testable import FlowWindow
import Testing

private let original = CGRect(x: 205, y: 151, width: 858, height: 647)
private let leftHalf = CGRect(x: 0, y: 30, width: 676, height: 769)
private let rightHalf = CGRect(x: 676, y: 30, width: 676, height: 769)

@MainActor
@Suite("WindowController")
struct WindowControllerTests {
    // MARK: Permissions

    @Test func untrustedProcessFailsWithoutTouchingWindows() async {
        let backend = FakeWindowBackend()
        backend.trusted = false
        backend.addWindow(.notes, "Notes", original)
        let result = await makeController(backend).perform(.move(.app(.notes), .leftHalf))
        #expect(result.status == .failed)
        #expect(result.error == .accessibilityNotTrusted)
        #expect(backend.mutations == 0)
    }

    // MARK: Activate

    @Test func activateVerifiesFrontmostAndWindow() async {
        let backend = FakeWindowBackend()
        backend.openCreatesWindowFor[KnownApp.notes.bundleIdentifier] = original
        let result = await makeController(backend).perform(.activate(.notes))
        #expect(result.status == .completed)
        #expect(result.observed.count == 1)
    }

    @Test func activateIsUnverifiedWhenAppNeverComesForward() async {
        let backend = FakeWindowBackend()
        backend.openActivates = false
        backend.addWindow(.notes, "Notes", original)
        let result = await makeController(backend).perform(.activate(.notes))
        #expect(result.status == .unverified)
    }

    @Test func activateWithoutWindowIsPartial() async {
        let backend = FakeWindowBackend()
        let result = await makeController(backend).perform(.activate(.mail))
        #expect(result.status == .partiallyCompleted)
    }

    @Test func activateMissingApp() async {
        let backend = FakeWindowBackend()
        backend.installed = []
        let result = await makeController(backend).perform(.activate(.safari))
        #expect(result.error == .appNotInstalled("com.apple.Safari"))
    }

    // MARK: Move + undo (milestone logic)

    @Test func moveLeftHalfThenUndoRestoresOriginal() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)

        let move = await controller.perform(.move(.app(.notes), .leftHalf))
        #expect(move.status == .completed)
        #expect(move.before == [original])
        #expect(move.expected == [leftHalf])
        #expect(move.observed.map(\.frame) == [leftHalf])
        #expect(move.windowServerConfirmed == true)
        #expect(move.undoToken != nil)
        #expect(backend.windows[id]?.frame == leftHalf)

        let undo = await controller.perform(.undo)
        #expect(undo.status == .completed)
        #expect(backend.windows[id]?.frame == original)
        #expect(!controller.canUndo)
    }

    @Test(arguments: [
        (WindowPosition.rightHalf, rightHalf),
        (.maximize, CGRect(x: 0, y: 30, width: 1352, height: 769)),
        (.center, CGRect(x: 247, y: 91, width: 858, height: 647)),
    ])
    func movePositions(position: WindowPosition, expected: CGRect) async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original)
        let result = await makeController(backend).perform(.move(.app(.notes), position))
        #expect(result.status == .completed)
        #expect(result.observed.first?.frame == expected)
    }

    @Test func appNotRunning() async {
        let result = await makeController(FakeWindowBackend()).perform(.move(.app(.mail), .leftHalf))
        #expect(result.error == .appNotRunning("Mail"))
    }

    @Test func noStandardWindow() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "", CGRect(x: 1, y: 1, width: 50, height: 50), standard: false)
        let result = await makeController(backend).perform(.move(.app(.notes), .leftHalf))
        #expect(result.error == .noWindow("Notes"))
    }

    @Test func activeSelectorUsesFrontmostApp() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.safari, "Apple", original)
        backend.front = backend.running[KnownApp.safari.bundleIdentifier]
        let result = await makeController(backend).perform(.move(.active, .rightHalf))
        #expect(result.status == .completed)
        #expect(backend.windows[id]?.frame == rightHalf)
    }

    // MARK: Multiple windows of one app (WIN-04)

    @Test func twoWindowsUseVerifiedFocus() async {
        let backend = FakeWindowBackend()
        let a = backend.addWindow(.notes, "Groceries", original)
        let b = backend.addWindow(.notes, "Ideas", original.offsetBy(dx: 30, dy: 30))
        backend.focused[backend.windows[b]!.app.pid] = b
        let result = await makeController(backend).perform(.move(.app(.notes), .leftHalf))
        #expect(result.status == .completed)
        #expect(backend.windows[b]?.frame == leftHalf)
        #expect(backend.windows[a]?.frame == original)
    }

    @Test func twoWindowsWithoutFocusAskWhichOne() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Groceries", original)
        backend.addWindow(.notes, "Ideas", original)
        let result = await makeController(backend).perform(.move(.app(.notes), .leftHalf))
        #expect(result.error == .ambiguousWindow(app: "Notes", candidates: ["Groceries", "Ideas"]))
        #expect(backend.mutations == 0)
    }

    @Test func titleSelectsAmongSameAppWindows() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Groceries", original)
        let ideas = backend.addWindow(.notes, "Ideas", original)
        let result = await makeController(backend).perform(.move(.app(.notes, title: "ideas"), .rightHalf))
        #expect(result.status == .completed)
        #expect(backend.windows[ideas]?.frame == rightHalf)
    }

    // MARK: Unsupported operations

    @Test func fullScreenIsUnsupported() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original, fullScreen: true)
        let result = await makeController(backend).perform(.move(.app(.notes), .leftHalf))
        #expect(result.status == .unsupported)
        #expect(result.unsupportedReason == .fullScreen)
        #expect(backend.mutations == 0)
    }

    @Test func nonResizableCanCenterButNotTile() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original, canResize: false)
        let controller = makeController(backend)
        #expect(await controller.perform(.move(.app(.notes), .leftHalf)).unsupportedReason == .notResizable)
        #expect(await controller.perform(.move(.app(.notes), .center)).status == .completed)
    }

    @Test func nonMovableIsUnsupported() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original, canMove: false)
        #expect(await makeController(backend).perform(.move(.app(.notes), .center)).unsupportedReason == .notMovable)
    }

    // MARK: Verification

    @Test func appMinimumSizeIsPartialButUndoable() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        backend.minimumSize[id] = CGSize(width: 800, height: 500)
        let controller = makeController(backend)
        let result = await controller.perform(.move(.app(.notes), .leftHalf))
        #expect(result.status == .partiallyCompleted)
        #expect(result.undoToken != nil)
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[id]?.frame == original)
    }

    @Test func ignoredChangeFailsWithoutUndo() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        backend.ignoresChanges = [id]
        let controller = makeController(backend)
        let result = await controller.perform(.move(.app(.notes), .leftHalf))
        #expect(result.status == .failed)
        #expect(!controller.canUndo)
    }

    // MARK: Undo safety

    @Test func undoRefusesWhenUserMovedWindowMeanwhile() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        _ = await controller.perform(.move(.app(.notes), .rightHalf))
        _ = await controller.perform(.move(.app(.notes), .leftHalf))
        backend.userSetFrame(id, CGRect(x: 300, y: 300, width: 500, height: 400))
        let undo = await controller.perform(.undo)
        #expect(undo.status == .failed)
        guard case .changedSinceAction = undo.error else { Issue.record("got \(String(describing: undo.error))"); return }
        #expect(backend.windows[id]?.frame == CGRect(x: 300, y: 300, width: 500, height: 400))
        #expect(!controller.canUndo, "history stops once reality diverges")
    }

    @Test func undoAfterWindowClosed() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        _ = await controller.perform(.move(.app(.notes), .leftHalf))
        backend.simulateUserClose(id)
        #expect(await controller.perform(.undo).error == .windowGone)
    }

    @Test func nothingToUndo() async {
        #expect(await makeController(FakeWindowBackend()).perform(.undo).error == .nothingToUndo)
    }

    @Test func undoWalksMultipleSteps() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        _ = await controller.perform(.move(.app(.notes), .rightHalf))
        _ = await controller.perform(.move(.app(.notes), .leftHalf))
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[id]?.frame == rightHalf)
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[id]?.frame == original)
    }

    // MARK: Minimize / restore (WIN-06)

    @Test func minimizeThenRestore() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        #expect(await controller.perform(.minimize(.app(.notes))).status == .completed)
        #expect(backend.windows[id]?.isMinimized == true)
        #expect(await controller.perform(.restore(.app(.notes))).status == .completed)
        #expect(backend.windows[id]?.isMinimized == false)
        #expect(backend.windows[id]?.frame == original)
    }

    @Test func undoMinimize() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        _ = await controller.perform(.minimize(.app(.notes)))
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[id]?.isMinimized == false)
    }

    @Test func restorePrefersWindowFlowMinimized() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Old", original, minimized: true)
        let mine = backend.addWindow(.notes, "Mine", original)
        let controller = makeController(backend)
        _ = await controller.perform(.minimize(.app(.notes)))
        let result = await controller.perform(.restore(.app(.notes)))
        #expect(result.status == .completed)
        #expect(backend.windows[mine]?.isMinimized == false)
    }

    @Test func restoreUsesFlowReferenceWhenWindowDropsOutOfAXList() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        let controller = makeController(backend)
        _ = await controller.perform(.minimize(.app(.notes)))
        backend.unlisted = [id]  // observed live with Stage Manager on
        #expect(await controller.perform(.restore(.app(.notes))).status == .completed)
        #expect(backend.windows[id]?.isMinimized == false)
    }

    @Test func droppedMinimizeIsReissuedOnce() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        backend.dropMinimizeRequests = 1
        #expect(await makeController(backend).perform(.minimize(.app(.notes))).status == .completed)
        #expect(backend.windows[id]?.isMinimized == true)
    }

    @Test func minimizeNeverConfirmedFails() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original)
        backend.dropMinimizeRequests = 5
        let controller = makeController(backend)
        let result = await controller.perform(.minimize(.app(.notes)))
        #expect(result.status == .failed)
        #expect(backend.mutations == 2, "bounded: one retry only")
        #expect(!controller.canUndo)
    }

    @Test func restoreWithNothingMinimized() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", original)
        #expect(await makeController(backend).perform(.restore(.app(.notes))).error == .noWindow("Notes"))
    }

    // MARK: Tile (WIN-01)

    @Test func tileTwoAppsAndUndoBoth() async {
        let backend = FakeWindowBackend()
        let mail = backend.addWindow(.mail, "Inbox", original)
        let cal = backend.addWindow(.calendar, "Calendar", original.offsetBy(dx: 20, dy: 20))
        let controller = makeController(backend)
        let result = await controller.perform(.tile(left: .mail, right: .calendar))
        #expect(result.status == .completed)
        #expect(backend.windows[mail]?.frame == leftHalf)
        #expect(backend.windows[cal]?.frame == rightHalf)
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[mail]?.frame == original)
        #expect(backend.windows[cal]?.frame == original.offsetBy(dx: 20, dy: 20))
    }

    @Test func tileAdjustsSplitForMinimumWidthAndUndoesInOneStep() async {
        // Observed live: Calendar enforces a 908 pt minimum width on a 1352 pt display.
        let backend = FakeWindowBackend()
        let notes = backend.addWindow(.notes, "Notes", original)
        let cal = backend.addWindow(.calendar, "Calendar", CGRect(x: 204, y: 170, width: 935, height: 598))
        backend.minimumSize[cal] = CGSize(width: 908, height: 500)
        let controller = makeController(backend)
        let result = await controller.perform(.tile(left: .notes, right: .calendar))
        #expect(result.status == .completed)
        #expect(backend.windows[notes]?.frame == CGRect(x: 0, y: 30, width: 444, height: 769))
        #expect(backend.windows[cal]?.frame == CGRect(x: 444, y: 30, width: 908, height: 769))
        #expect(result.before == [original, CGRect(x: 204, y: 170, width: 935, height: 598)])
        #expect(await controller.perform(.undo).status == .completed)
        #expect(backend.windows[notes]?.frame == original)
        #expect(backend.windows[cal]?.frame == CGRect(x: 204, y: 170, width: 935, height: 598))
        #expect(!controller.canUndo)
    }

    @Test func tileThatCannotFitStaysPartial() async {
        let backend = FakeWindowBackend()
        let mail = backend.addWindow(.mail, "Inbox", original)
        let cal = backend.addWindow(.calendar, "Calendar", original)
        backend.minimumSize[mail] = CGSize(width: 800, height: 400)
        backend.minimumSize[cal] = CGSize(width: 800, height: 400)
        let result = await makeController(backend).perform(.tile(left: .mail, right: .calendar))
        #expect(result.status == .partiallyCompleted)
        #expect(result.undoToken != nil)
    }

    @Test func tileSameAppUnsupported() async {
        let result = await makeController(FakeWindowBackend()).perform(.tile(left: .mail, right: .mail))
        #expect(result.unsupportedReason == .sameApp)
    }

    // MARK: Resize (WIN-02)

    @Test func resizeWiderUsesFixedStep() async {
        let backend = FakeWindowBackend()
        let id = backend.addWindow(.notes, "Notes", original)
        #expect(await makeController(backend).perform(.resize(.app(.notes), .wider)).status == .completed)
        #expect(backend.windows[id]?.frame.width == original.width + 120)
    }

    @Test func resizeAtScreenLimitIsUnsupported() async {
        let backend = FakeWindowBackend()
        backend.addWindow(.notes, "Notes", CGRect(x: 0, y: 30, width: 1352, height: 769))
        let result = await makeController(backend).perform(.resize(.app(.notes), .larger))
        #expect(result.unsupportedReason == .atSizeLimit)
    }
}
