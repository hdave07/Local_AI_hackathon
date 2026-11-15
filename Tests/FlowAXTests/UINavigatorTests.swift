import CoreGraphics
@testable import FlowAX
import FlowCore
import FlowWindow
import Testing

@MainActor
@Suite("UINavigator")
struct UINavigatorTests {
    // MARK: Permissions and app coverage

    @Test func untrustedProcessDoesNothing() async {
        let b = mailLikeBackend()
        b.trusted = false
        let r = await makeNavigator(b).perform(.click(.parse("save"), .frontmost))
        #expect(r.status == .failed)
        #expect(r.error == .accessibilityNotTrusted)
        #expect(b.log.isEmpty)
    }

    @Test func inaccessibleAppIsUnsupported() async {
        let b = FakeUIBackend()
        b.add(.init(key: "close", role: "AXButton", subrole: "AXCloseButton", frame: CGRect(x: 0, y: 0, width: 12, height: 12), actions: ["AXPress"]))
        b.add(.init(key: "canvas", role: "AXGroup", frame: CGRect(x: 0, y: 20, width: 800, height: 600)))
        let numbers = await makeNavigator(b).perform(.showNumbers(nil, .frontmost))
        #expect(numbers.status == .unsupported)
        #expect(numbers.error == .inaccessibleApp("FakeApp"))
        let click = await makeNavigator(b).perform(.click(.parse("draw"), .frontmost))
        #expect(click.error == .inaccessibleApp("FakeApp"))
    }

    @Test func notFound() async {
        let r = await makeNavigator(mailLikeBackend()).perform(.click(.parse("Forward"), .frontmost))
        #expect(r.status == .failed)
        #expect(r.error == .notFound("Forward"))
    }

    @Test func bringsTargetForwardWhenConfigured() async {
        let b = mailLikeBackend()
        _ = await makeNavigator(b, bringToFront: true).perform(.click(.parse("save"), .frontmost))
        #expect(b.broughtToFront == 1)
    }

    // MARK: Click

    @Test func clickUniqueControlVerifiesVisibleChange() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.click(.parse("the Save button"), .frontmost))
        #expect(r.status == .completed)
        #expect(b.log == ["press save"])
        #expect(r.evidence.contains("now shows “Status: saved”"))
    }

    @Test func clickWithoutObservableChangeIsUnverified() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.click(.parse("help"), .frontmost))
        #expect(r.status == .unverified)
        #expect(b.log == ["press noop"])
    }

    @Test func clickSelectsRows() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.click(.parse("Sarah meeting tomorrow"), .frontmost))
        #expect(r.status == .completed)
        #expect(b.log == ["select row1"])
        #expect(b["row1"]?.selected == true)
    }

    @Test func disabledControlIsRefused() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.click(.parse("delete"), .frontmost))
        #expect(r.error == .targetDisabled("“Delete” button"))
        #expect(b.log.isEmpty)
    }

    @Test func nonPressableTargetIsUnsupported() async throws {
        let b = mailLikeBackend()
        let nav = makeNavigator(b)
        let s = try b.snapshot(of: b.app, limits: SnapshotLimits())
        let status = try #require(s.elements.first { $0.label == "Status: ready" })
        let r = await nav.perform(.click, on: status, in: b.app)
        #expect(r.status == .unsupported)
        guard case .notPressable = r.error else { Issue.record("got \(String(describing: r.error))"); return }
    }

    @Test func consequentialControlsAreNeverPressed() async {
        let b = mailLikeBackend()
        b.button("send", "Send", at: CGRect(x: 400, y: 40, width: 60, height: 22))
        b.button("trash", "Move to Trash", at: CGRect(x: 470, y: 40, width: 90, height: 22))
        let nav = makeNavigator(b)
        for target in ["send", "move to trash"] {
            let r = await nav.perform(.click(.parse(target), .frontmost))
            #expect(r.status == .unsupported, "\(target)")
            guard case .consequentialControl = r.error else { Issue.record("got \(String(describing: r.error))"); return }
        }
        #expect(b.log.isEmpty)
    }

    @Test func consequentialWordsAreWholeWords() {
        #expect(UINavigator.isConsequential("Send"))
        #expect(UINavigator.isConsequential("Delete Draft"))
        #expect(!UINavigator.isConsequential("Sender details"))
        #expect(!UINavigator.isConsequential("Remove Volatile"))
    }

    // MARK: Ambiguity and numbers

    @Test func indistinguishableControlsAskInsteadOfClicking() async {
        let b = mailLikeBackend()
        let overlay = RecordingOverlay()
        let r = await makeNavigator(b, overlay: overlay).perform(.click(.parse("reply"), .frontmost))
        #expect(r.status == .needsClarification)
        #expect(b.log.isEmpty, "never guesses")
        #expect(r.clarification?.options.map(\.number) == [1, 2])
        #expect(r.clarification?.prompt.contains("identical") == true)
        #expect(overlay.isVisible)
        #expect(overlay.shown.last?.map(\.element.frame.minX) == [80, 150])
    }

    @Test func chooseNumberActsOnThatElementAndHidesOverlay() async {
        let b = mailLikeBackend()
        let overlay = RecordingOverlay()
        let nav = makeNavigator(b, overlay: overlay)
        _ = await nav.perform(.click(.parse("reply"), .frontmost))
        let r = await nav.perform(.choose(2))
        #expect(r.status == .completed)
        #expect(b.log == ["press replyB"])
        #expect(b["status"]?.value == "Status: reply B")
        #expect(!overlay.isVisible)
        #expect(nav.currentNumbers.isEmpty, "numbers are single-use")
    }

    @Test func showNumbersListsActionableElementsInReadingOrder() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.showNumbers(nil, .frontmost))
        #expect(r.status == .completed)
        let labels = r.clarification?.options.map(\.element.label) ?? []
        #expect(labels.first == "Close")
        #expect(labels.contains("Search mail"))
        #expect(!labels.contains("Delete"), "disabled controls are not offered")
        #expect(!labels.contains("Status: ready"), "plain text is not a target")
    }

    @Test func choosingANumberedTextFieldFocusesIt() async throws {
        let b = mailLikeBackend()
        let nav = makeNavigator(b)
        let shown = await nav.perform(.showNumbers(nil, .frontmost))
        let n = try #require(shown.clarification?.options.first { $0.element.label == "Search mail" }?.number)
        let r = await nav.perform(.choose(n))
        #expect(r.status == .completed)
        #expect(b.log == ["focus search"])
        #expect(b["search"]?.focused == true)
    }

    @Test func staleNumbersAreRefusedAfterLayoutChange() async {
        let b = mailLikeBackend()
        let overlay = RecordingOverlay()
        let nav = makeNavigator(b, overlay: overlay)
        _ = await nav.perform(.click(.parse("reply"), .frontmost))
        b["replyA"]?.frame.origin.x += 40  // UI changed after numbers were shown
        let r = await nav.perform(.choose(1))
        #expect(r.error == .staleNumbers)
        #expect(b.log.isEmpty)
        #expect(!overlay.isVisible)
        #expect(await nav.perform(.choose(1)).error == .noActiveNumbers, "stale numbers are discarded")
    }

    @Test func textOnlyChangesDoNotInvalidateNumbers() async {
        let b = mailLikeBackend()
        let nav = makeNavigator(b)
        _ = await nav.perform(.click(.parse("reply"), .frontmost))
        b.setStatus("Status: clock ticked")
        #expect(await nav.perform(.choose(1)).status == .completed)
    }

    @Test func numberErrors() async {
        let b = mailLikeBackend()
        let nav = makeNavigator(b)
        #expect(await nav.perform(.choose(1)).error == .noActiveNumbers)
        _ = await nav.perform(.click(.parse("reply"), .frontmost))
        #expect(await nav.perform(.choose(5)).error == .numberOutOfRange(5, count: 2))
        #expect(await nav.perform(.hideNumbers).status == .completed)
        #expect(await nav.perform(.choose(1)).error == .noActiveNumbers)
    }

    @Test func lowConfidenceAsksForConfirmation() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.click(.parse("eet"), .frontmost))
        #expect(r.status == .needsClarification)
        #expect(r.clarification?.prompt.hasPrefix("Did you mean") == true)
        #expect(b.log.isEmpty)
    }

    // MARK: Revalidation (NAV-05, ERR-02)

    private func staleScenario(_ mutate: (FakeUIBackend) -> Void) async throws -> (NavigationResult, FakeUIBackend) {
        let b = mailLikeBackend()
        let nav = makeNavigator(b)
        let s = try b.snapshot(of: b.app, limits: SnapshotLimits())
        let save = try #require(s.elements.first { $0.label == "Save" })
        mutate(b)
        return (await nav.perform(.click, on: save, in: b.app), b)
    }

    @Test func removedTargetIsNeverClicked() async throws {
        let (r, b) = try await staleScenario { $0["save"] = nil }
        #expect(r.error == .targetGone)
        #expect(b.log.isEmpty)
    }

    @Test func renamedTargetIsRefused() async throws {
        let (r, b) = try await staleScenario { $0["save"]?.title = "Delete All" }
        guard case .targetChanged(let why) = r.error else { Issue.record("got \(String(describing: r.error))"); return }
        #expect(why.contains("Delete All"))
        #expect(b.log.isEmpty)
    }

    @Test func movedTargetIsRefused() async throws {
        let (r, b) = try await staleScenario { $0["save"]?.frame.origin.y += 30 }
        guard case .targetChanged = r.error else { Issue.record("got \(String(describing: r.error))"); return }
        #expect(b.log.isEmpty)
    }

    @Test func targetDisabledMeanwhileIsRefused() async throws {
        let (r, b) = try await staleScenario { $0["save"]?.enabled = false }
        guard case .targetDisabled = r.error else { Issue.record("got \(String(describing: r.error))"); return }
        #expect(b.log.isEmpty)
    }

    @Test func unchangedTargetPassesRevalidation() async throws {
        let (r, b) = try await staleScenario { _ in }
        #expect(r.status == .completed)
        #expect(b.log == ["press save"])
    }

    // MARK: Focus

    @Test func focusVerifiedByReread() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.focus(.parse("the search field"), .frontmost))
        #expect(r.status == .completed)
        #expect(b["search"]?.focused == true)
    }

    @Test func focusNotTakenFails() async {
        let b = mailLikeBackend()
        b.ignoreFocus = true
        let r = await makeNavigator(b).perform(.focus(.parse("search"), .frontmost))
        #expect(r.status == .failed)
    }

    // MARK: Scroll

    @Test func scrollDefaultAreaAndVerifyDirection() async {
        let b = mailLikeBackend()
        let r = await makeNavigator(b).perform(.scroll(nil, .down, .frontmost))
        #expect(r.status == .completed)
        #expect(b["list"]?.scroll == 0.25)
    }

    @Test func scrollAtLimitDoesNothing() async {
        let b = mailLikeBackend()
        b["list"]?.scroll = 1
        let r = await makeNavigator(b).perform(.scroll(.parse("messages"), .down, .frontmost))
        #expect(r.error == .atScrollLimit("bottom"))
        #expect(b.log.isEmpty)
    }

    @Test func scrollInWrongDirectionFails() async {
        let b = mailLikeBackend()
        b["list"]?.scroll = 0.5
        b.invertScroll = true
        let r = await makeNavigator(b).perform(.scroll(nil, .down, .frontmost))
        #expect(r.status == .failed)
    }

    @Test func scrollWithoutMovementIsUnverified() async {
        let b = mailLikeBackend()
        b.ignoreScroll = true
        #expect(await makeNavigator(b).perform(.scroll(nil, .down, .frontmost)).status == .unverified)
    }

    @Test func twoEqualScrollAreasAsk() async {
        let b = FakeUIBackend()
        b.scrollArea("a", "Left", at: CGRect(x: 0, y: 0, width: 300, height: 300))
        b.scrollArea("b", "Right", at: CGRect(x: 310, y: 0, width: 300, height: 300))
        let r = await makeNavigator(b).perform(.scroll(nil, .down, .frontmost))
        #expect(r.status == .needsClarification)
        #expect(b.log.isEmpty)
    }

    @Test func noScrollArea() async {
        let b = FakeUIBackend()
        b.button("ok", "OK", at: CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(await makeNavigator(b).perform(.scroll(nil, .down, .frontmost)).status == .unsupported)
    }
}
