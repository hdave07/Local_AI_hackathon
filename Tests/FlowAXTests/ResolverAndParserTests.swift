import CoreGraphics
@testable import FlowAX
import FlowCore
import FlowWindow
import Testing

@Suite("TargetReference parsing")
struct TargetReferenceTests {
    @Test(arguments: [
        ("the second Reply button", ["reply"], RoleHint.button as RoleHint?, Ordinal.index(2) as Ordinal?),
        ("Save", ["save"], nil, nil),
        ("the search field", ["search"], .textField, nil),
        ("Show Sidebar button", ["show", "sidebar"], .button, nil),
        ("the text field", [], .textField, nil),
        ("last row", [], .row, .last),
        ("Notify me checkbox", ["notify", "me"], .checkbox, nil),
        ("“Reply All”!", ["reply", "all"], nil, nil),
    ])
    func parses(raw: String, words: [String], hint: RoleHint?, ordinal: Ordinal?) {
        let r = TargetReference.parse(raw)
        #expect(r.words == words)
        #expect(r.roleHint == hint)
        #expect(r.ordinal == ordinal)
    }

    @Test func labelCleaningStripsBidiMarks() {
        #expect(LabelText.clean("\u{200E}48.88\u{200E}") == "48.88")
        #expect(LabelText.words("Café — Menu") == ["cafe", "menu"])
    }
}

@MainActor
@Suite("TargetResolver")
struct TargetResolverTests {
    func snapshot(_ b: FakeUIBackend) throws -> UISnapshot { try b.snapshot(of: b.app, limits: SnapshotLimits()) }

    @Test func exactBeatsPrefix() throws {
        let b = mailLikeBackend()
        b["replyB"] = nil
        guard case .unique(let e) = TargetResolver.resolve(.parse("reply"), intent: .click, in: try snapshot(b)) else {
            Issue.record("expected unique"); return
        }
        #expect(e.label == "Reply")
    }

    @Test func identicalControlsAreAmbiguous() throws {
        guard case .ambiguous(let es) = TargetResolver.resolve(.parse("reply"), intent: .click, in: try snapshot(mailLikeBackend())) else {
            Issue.record("expected ambiguous"); return
        }
        #expect(es.map(\.frame.minX) == [80, 150], "reading order")
    }

    @Test func ordinalDisambiguatesInReadingOrder() throws {
        guard case .unique(let e) = TargetResolver.resolve(.parse("the second reply button"), intent: .click, in: try snapshot(mailLikeBackend())) else {
            Issue.record("expected unique"); return
        }
        #expect(e.frame.minX == 150)
        #expect(TargetResolver.resolve(.parse("third reply"), intent: .click, in: try snapshot(mailLikeBackend())) == .notFound)
    }

    @Test func fullLabelWins() throws {
        guard case .unique(let e) = TargetResolver.resolve(.parse("reply all"), intent: .click, in: try snapshot(mailLikeBackend())) else {
            Issue.record("expected unique"); return
        }
        #expect(e.label == "Reply All")
    }

    @Test func numberWordsAndSynonyms() throws {
        let b = FakeUIBackend()
        b.button("seven", "7", at: CGRect(x: 0, y: 0, width: 40, height: 40))
        b.button("add", "Add", at: CGRect(x: 50, y: 0, width: 40, height: 40))
        let s = try snapshot(b)
        guard case .unique(let seven) = TargetResolver.resolve(.parse("seven"), intent: .click, in: s),
            case .unique(let add) = TargetResolver.resolve(.parse("plus"), intent: .click, in: s)
        else { Issue.record("expected unique"); return }
        #expect(seven.label == "7")
        #expect(add.label == "Add")
    }

    @Test func partialTextIsLowConfidence() throws {
        guard case .lowConfidence(let es) = TargetResolver.resolve(.parse("eet"), intent: .click, in: try snapshot(mailLikeBackend())) else {
            Issue.record("expected low confidence"); return
        }
        #expect(es.first?.label == "Sarah — Meeting tomorrow")
    }

    @Test func roleHintFilters() throws {
        let b = mailLikeBackend()
        b.button("searchBtn", "Search", at: CGRect(x: 400, y: 80, width: 60, height: 22))
        guard case .unique(let field) = TargetResolver.resolve(.parse("the search field"), intent: .focus, in: try snapshot(b)),
            case .unique(let button) = TargetResolver.resolve(.parse("search button"), intent: .click, in: try snapshot(b))
        else { Issue.record("expected unique"); return }
        #expect(field.kind == .textInput)
        #expect(button.kind == .button)
    }

    @Test func invisibleElementsAreIgnored() throws {
        let b = mailLikeBackend()
        b["save"]?.visible = false
        #expect(TargetResolver.resolve(.parse("save"), intent: .click, in: try snapshot(b)) == .notFound)
    }

    @Test func containerAndChildMatchingKeepsChild() throws {
        let b = FakeUIBackend()
        b.add(.init(key: "group", role: "AXGroup", desc: "Send", frame: CGRect(x: 0, y: 0, width: 100, height: 40), actions: ["AXPress"]))
        b.button("inner", "Send", at: CGRect(x: 10, y: 10, width: 60, height: 20), parent: "group")
        guard case .unique(let e) = TargetResolver.resolve(.parse("send"), intent: .click, in: try snapshot(b)) else {
            Issue.record("expected unique"); return
        }
        #expect(e.role == "AXButton")
    }

    @Test func rowsInheritLabelAndAreSelectable() throws {
        guard case .unique(let e) = TargetResolver.resolve(.parse("sarah meeting"), intent: .click, in: try snapshot(mailLikeBackend())) else {
            Issue.record("expected unique"); return
        }
        #expect(e.kind == .row)
    }

    @Test func unlabeledElementsAreNotNameTargetsButAreNumbered() throws {
        let b = FakeUIBackend()
        b.add(.init(key: "star", role: "AXButton", frame: CGRect(x: 0, y: 0, width: 30, height: 20), actions: ["AXPress"]))
        let s = try snapshot(b)
        #expect(TargetResolver.resolve(.parse("star"), intent: .click, in: s) == .notFound)
        #expect(s.actionable.count == 1)
        #expect(s.actionable[0].displayName == "unlabeled button")
    }

    @Test func secureFieldValueIsNeverStored() {
        let e = UIElementInfo(id: ElementID(epoch: 1, index: 0), role: "AXTextField", subrole: "AXSecureTextField",
                              value: "hunter2", placeholder: "Password", frame: .zero, isSecure: true)
        #expect(e.value == nil)
        #expect(e.label == "Password")
    }
}

@Suite("NavCommandParser")
struct NavCommandParserTests {
    let running: (String) -> Bool = { ["calculator", "system settings"].contains($0.lowercased()) }

    @Test func parsesCommands() throws {
        #expect(try NavCommandParser.parse("click the Save button") == .click(.parse("the Save button"), .frontmost))
        #expect(try NavCommandParser.parse("press seven in Calculator", isRunningApp: running) == .click(.parse("seven"), .named("Calculator")))
        #expect(try NavCommandParser.parse("focus on the search field") == .focus(.parse("the search field"), .frontmost))
        #expect(try NavCommandParser.parse("scroll down") == .scroll(nil, .down, .frontmost))
        #expect(try NavCommandParser.parse("scroll top sidebar in System Settings", isRunningApp: running)
            == .scroll(.parse("sidebar"), .top, .named("System Settings")))
        #expect(try NavCommandParser.parse("show numbers") == .showNumbers(nil, .frontmost))
        #expect(try NavCommandParser.parse("show numbers for reply") == .showNumbers(.parse("reply"), .frontmost))
        #expect(try NavCommandParser.parse("choose 3") == .choose(3))
        #expect(try NavCommandParser.parse("2") == .choose(2))
        #expect(try NavCommandParser.parse("hide numbers") == .hideNumbers)
        #expect(try NavCommandParser.parse("inspect in app flow-nav-fixture") == .inspect(.named("flow-nav-fixture")))
    }

    @Test func inOnlyScopesToRunningApps() throws {
        // "Dock" is not a running regular app here, so "in Dock" stays part of the label.
        #expect(try NavCommandParser.parse("click Keep in Dock", isRunningApp: running) == .click(.parse("Keep in Dock"), .frontmost))
    }

    @Test(arguments: ["", "click", "scroll sideways", "choose zero", "hide everything", "dance"])
    func rejects(input: String) {
        #expect(throws: NavParseError.self) { try NavCommandParser.parse(input) }
    }

    @Test func flowActionBridge() {
        #expect(NavCommand(.clickElement(label: "Reply")) == .click(.parse("Reply"), .frontmost))
        #expect(NavCommand(.focus(label: "To")) == .focus(.parse("To"), .frontmost))
        #expect(NavCommand(.scroll(.down)) == .scroll(nil, .down, .frontmost))
        #expect(NavCommand(.activateApp(.notes)) == nil)
    }
}

@Suite("Overlay geometry")
struct OverlayGeometryTests {
    @Test func axToAppKit() {
        // Primary display 878 pt tall: an element at AX y=30 with height 20 sits at AppKit y=828.
        #expect(OverlayGeometry.appKitRect(fromAX: CGRect(x: 10, y: 30, width: 50, height: 20), primaryScreenHeight: 878)
            == CGRect(x: 10, y: 828, width: 50, height: 20))
    }

    @Test func badgeStaysOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1352, height: 878)
        let badge = OverlayGeometry.badgeRect(for: CGRect(x: 0, y: 860, width: 40, height: 18), size: CGSize(width: 22, height: 22), within: bounds)
        #expect(bounds.contains(badge))
    }
}
