import CoreGraphics
import FlowCore
@testable import FlowWindow
import Testing

@Suite("WindowGeometry")
struct WindowGeometryTests {
    let screen = CGRect(x: 0, y: 30, width: 1351, height: 769)

    @Test func halvesCoverOddWidthScreenExactly() {
        let l = WindowGeometry.targetFrame(for: .leftHalf, current: .zero, screen: screen)
        let r = WindowGeometry.targetFrame(for: .rightHalf, current: .zero, screen: screen)
        #expect(l.maxX == r.minX)
        #expect(l.width + r.width == screen.width)
        #expect(l.minY == screen.minY && r.height == screen.height)
    }

    @Test func centerShrinksOversizedWindowToScreen() {
        let c = WindowGeometry.targetFrame(for: .center, current: CGRect(x: 0, y: 0, width: 3000, height: 2000), screen: screen)
        #expect(c.size == screen.size)
    }

    @Test func resizeKeepsWindowOnScreen() {
        let nearEdge = CGRect(x: 1200, y: 600, width: 140, height: 190)
        let r = WindowGeometry.resized(nearEdge, change: .larger, screen: screen)
        #expect(r.maxX <= screen.maxX && r.maxY <= screen.maxY)
        #expect(r.width == 260 && r.height == 290)
    }

    @Test func resizeRespectsMinimum() {
        let r = WindowGeometry.resized(CGRect(x: 10, y: 40, width: 300, height: 200), change: .smaller, screen: screen)
        #expect(r.width == WindowGeometry.minimumSize.width)
        #expect(r.height == WindowGeometry.minimumSize.height)
    }

    @Test func appKitToAXConversion() {
        // Verified display: frame 1352×878, visibleFrame (0,79,1352,769) → AX (0,30,1352,769).
        let ax = WindowGeometry.axFrame(fromAppKit: CGRect(x: 0, y: 79, width: 1352, height: 769), primaryScreenHeight: 878)
        #expect(ax == CGRect(x: 0, y: 30, width: 1352, height: 769))
    }

    @Test func tolerance() {
        let a = CGRect(x: 0, y: 30, width: 676, height: 769)
        #expect(WindowGeometry.approximatelyEqual(a, CGRect(x: 0, y: 30, width: 676, height: 768)))
        #expect(!WindowGeometry.approximatelyEqual(a, CGRect(x: 0, y: 30, width: 676, height: 760)))
    }
}

@Suite("Typed command parser")
struct WindowCommandParserTests {
    @Test(arguments: [
        ("activate notes", TypedCommand.window(.activate(.notes))),
        ("Switch to Mail", .window(.activate(.mail))),
        ("move notes left_half", .window(.move(.app(.notes), .leftHalf))),
        ("move active right", .window(.move(.active, .rightHalf))),
        ("move notes \"Groceries List\" maximize", .window(.move(.app(.notes, title: "Groceries List"), .maximize))),
        ("resize safari wider", .window(.resize(.app(.safari), .wider))),
        ("tile mail and calendar", .window(.tile(left: .mail, right: .calendar))),
        ("tile calendar notes", .window(.tile(left: .calendar, right: .notes))),
        ("minimize notes", .window(.minimize(.app(.notes)))),
        ("restore active", .window(.restore(.active))),
        ("undo", .window(.undo)),
        ("list finder", .list(.finder)),
    ])
    func parses(input: String, expected: TypedCommand) throws {
        #expect(try WindowCommandParser.parse(input) == expected)
    }

    @Test(arguments: [
        "", "fly notes", "activate terminal", "move notes", "move notes diagonal", "resize notes 800x600",
        "tile mail", "undo everything", "move notes \"unterminated left_half",
    ])
    func rejects(input: String) {
        #expect(throws: CommandParseError.self) { try WindowCommandParser.parse(input) }
    }
}

@Suite("FlowAction bridge")
struct FlowActionBridgeTests {
    @Test func mapsWindowActions() {
        #expect(WindowCommand(.activateApp(.notes)) == .activate(.notes))
        #expect(WindowCommand(.moveWindow(.active, .leftHalf)) == .move(.active, .leftHalf))
        #expect(WindowCommand(.resizeWindow(.app(.mail), .taller)) == .resize(.app(.mail), .taller))
        #expect(WindowCommand(.tileWindows(left: .mail, right: .calendar)) == .tile(left: .mail, right: .calendar))
    }

    @Test func ignoresNonWindowActions() {
        #expect(WindowCommand(.insertText("hi")) == nil)
        #expect(WindowCommand(.requestSend) == nil)
    }
}
