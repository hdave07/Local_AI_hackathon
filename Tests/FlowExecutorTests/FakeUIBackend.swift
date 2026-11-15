// Copied from the module's own test target (test targets cannot import each other).
import CoreGraphics
@testable import FlowAX
import FlowCore
import FlowWindow

/// Simulated Accessibility backend. Nodes are keyed so tests can mutate the "live" UI
/// between inspection and execution (remove, rename, move, disable).
@MainActor
final class FakeUIBackend: UIBackend {
    struct Node {
        var key: String
        var role: String
        var subrole: String? = nil
        var title: String? = nil
        var desc: String? = nil
        var value: String? = nil
        var placeholder: String? = nil
        var identifier: String? = nil
        var frame: CGRect
        var enabled = true
        var focused = false
        var selected: Bool? = nil
        var actions: [String] = []
        var canFocus = false
        var canSelect = false
        var visible = true
        var parent: String? = nil
        var scroll: Double? = nil
        var inherited: String? = nil
    }

    var trusted = true
    var app = AppHandle(pid: 4242, bundleID: "com.example.fake", name: "FakeApp")
    var windowTitle = "Fake Window"
    var nodes: [Node] = []
    var onPress: [String: (FakeUIBackend) -> Void] = [:]
    var ignoreFocus = false
    var invertScroll = false
    var ignoreScroll = false
    private(set) var log: [String] = []
    private(set) var broughtToFront = 0
    private var epochs: [Int: [String]] = [:]
    private var nextEpoch = 1

    // MARK: Builders

    @discardableResult
    func add(_ node: Node) -> String {
        nodes.append(node)
        return node.key
    }

    func button(_ key: String, _ title: String, at frame: CGRect, parent: String? = nil, onPress: ((FakeUIBackend) -> Void)? = nil) {
        add(Node(key: key, role: "AXButton", title: title, frame: frame, actions: ["AXPress"], parent: parent))
        if let onPress { self.onPress[key] = onPress }
    }

    func text(_ key: String, _ value: String, at frame: CGRect, parent: String? = nil) {
        add(Node(key: key, role: "AXStaticText", value: value, frame: frame, parent: parent))
    }

    func field(_ key: String, placeholder: String, at frame: CGRect) {
        add(Node(key: key, role: "AXTextField", placeholder: placeholder, frame: frame, canFocus: true))
    }

    func scrollArea(_ key: String, _ label: String?, at frame: CGRect, value: Double = 0) {
        add(Node(key: key, role: "AXScrollArea", desc: label, frame: frame,
                 actions: ["AXScrollDownByPage", "AXScrollUpByPage"], scroll: value))
    }

    subscript(key: String) -> Node? {
        get { nodes.first { $0.key == key } }
        set {
            if let i = nodes.firstIndex(where: { $0.key == key }) {
                if let newValue { nodes[i] = newValue } else { nodes.remove(at: i) }
            }
        }
    }

    func setStatus(_ text: String) { self["status"]?.value = text }

    // MARK: UIBackend

    func isAccessibilityTrusted() -> Bool { trusted }

    func resolveApp(_ scope: AppScope) throws(NavigationError) -> AppHandle {
        if case .named(let name) = scope, name.lowercased() != app.name.lowercased() { throw .appNotFound(name) }
        return app
    }

    func bringToFront(_ app: AppHandle) async -> Bool {
        broughtToFront += 1
        return true
    }

    func snapshot(of app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot {
        let epoch = nextEpoch
        nextEpoch += 1
        epochs[epoch] = nodes.map(\.key)
        return makeSnapshot(epoch: epoch)
    }

    func observe(_ app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot {
        makeSnapshot(epoch: -1)
    }

    private func makeSnapshot(epoch: Int) -> UISnapshot {
        let keys = nodes.map(\.key)
        let elements = nodes.enumerated().map { i, n in info(n, ElementID(epoch: epoch, index: i), parentIndex: n.parent.flatMap { keys.firstIndex(of: $0) }) }
        return UISnapshot(epoch: epoch, app: app, windowTitle: windowTitle,
                          windowFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), elements: elements)
    }

    private func info(_ n: Node, _ id: ElementID, parentIndex: Int?) -> UIElementInfo {
        UIElementInfo(id: id, role: n.role, subrole: n.subrole, title: n.title, descriptionText: n.desc, value: n.value,
                      placeholder: n.placeholder, identifier: n.identifier, inheritedLabel: n.inherited, isEnabled: n.enabled, isFocused: n.focused,
                      isSelected: n.selected, frame: n.frame, actions: n.actions, canFocus: n.canFocus,
                      canSelect: n.canSelect, isVisible: n.visible, parentIndex: parentIndex)
    }

    private func node(_ id: ElementID) throws(NavigationError) -> Node {
        guard let keys = epochs[id.epoch], keys.indices.contains(id.index), let n = self[keys[id.index]] else {
            throw .targetGone
        }
        return n
    }

    func refresh(_ id: ElementID) throws(NavigationError) -> UIElementInfo {
        info(try node(id), id, parentIndex: nil)
    }

    func press(_ id: ElementID) throws(NavigationError) {
        let n = try node(id)
        log.append("press \(n.key)")
        onPress[n.key]?(self)
    }

    func setFocused(_ id: ElementID) throws(NavigationError) {
        let n = try node(id)
        log.append("focus \(n.key)")
        guard !ignoreFocus else { return }
        for i in nodes.indices { nodes[i].focused = nodes[i].key == n.key }
    }

    func setSelected(_ id: ElementID) throws(NavigationError) {
        let n = try node(id)
        log.append("select \(n.key)")
        self[n.key]?.selected = true
    }

    func scroll(_ id: ElementID, _ direction: ScrollDirection) throws(NavigationError) {
        let n = try node(id)
        log.append("scroll \(n.key) \(direction.rawValue)")
        guard !ignoreScroll, var v = n.scroll else { return }
        switch direction {
        case .down: v += invertScroll ? -0.25 : 0.25
        case .up: v -= invertScroll ? -0.25 : 0.25
        case .top: v = 0
        case .bottom: v = 1
        }
        self[n.key]?.scroll = min(1, max(0, v))
    }

    func scrollPosition(_ id: ElementID) -> ScrollPosition? {
        guard let n = try? node(id) else { return nil }
        return ScrollPosition(vertical: n.scroll, contentMarker: [])
    }

    func isFocusedElement(_ id: ElementID, in app: AppHandle) -> Bool {
        (try? node(id))?.focused ?? false
    }
}

/// Records what the overlay was asked to show.
@MainActor
final class RecordingOverlay: OverlayPresenting {
    private(set) var shown: [[NumberedTarget]] = []
    private(set) var isVisible = false
    func show(_ targets: [NumberedTarget]) { shown.append(targets); isVisible = true }
    func hide() { isVisible = false }
}

@MainActor
func makeNavigator(_ backend: FakeUIBackend, overlay: OverlayPresenting? = nil, bringToFront: Bool = false) -> UINavigator {
    var c = UINavigator.Configuration()
    c.settleTimeout = .milliseconds(40)
    c.pollInterval = .milliseconds(2)
    c.bringTargetToFront = bringToFront
    return UINavigator(backend: backend, overlay: overlay, configuration: c)
}

/// A mail-like fixture: status text, Save, two identical Reply buttons, Reply All,
/// a search field, a disabled button, a selectable row, and a scroll area.
@MainActor
func mailLikeBackend() -> FakeUIBackend {
    let b = FakeUIBackend()
    b.text("status", "Status: ready", at: CGRect(x: 10, y: 10, width: 200, height: 18))
    b.button("save", "Save", at: CGRect(x: 10, y: 40, width: 60, height: 22)) { $0.setStatus("Status: saved") }
    b.button("replyA", "Reply", at: CGRect(x: 80, y: 40, width: 60, height: 22)) { $0.setStatus("Status: reply A") }
    b.button("replyB", "Reply", at: CGRect(x: 150, y: 40, width: 60, height: 22)) { $0.setStatus("Status: reply B") }
    b.button("replyAll", "Reply All", at: CGRect(x: 220, y: 40, width: 80, height: 22)) { $0.setStatus("Status: reply all") }
    b.button("noop", "Help", at: CGRect(x: 310, y: 40, width: 50, height: 22))
    b.field("search", placeholder: "Search mail", at: CGRect(x: 10, y: 80, width: 200, height: 22))
    b.add(.init(key: "disabled", role: "AXButton", title: "Delete", frame: CGRect(x: 220, y: 80, width: 60, height: 22),
                enabled: false, actions: ["AXPress"]))
    b.add(.init(key: "row1", role: "AXRow", frame: CGRect(x: 10, y: 120, width: 300, height: 24), selected: false, canSelect: true, inherited: "Sarah — Meeting tomorrow"))
    b.text("row1text", "Sarah — Meeting tomorrow", at: CGRect(x: 14, y: 122, width: 200, height: 18), parent: "row1")
    b.scrollArea("list", "Messages", at: CGRect(x: 10, y: 160, width: 400, height: 300))
    b.add(.init(key: "close", role: "AXButton", subrole: "AXCloseButton", frame: CGRect(x: 2, y: 2, width: 12, height: 12), actions: ["AXPress"]))
    return b
}
