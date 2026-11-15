import AppKit
import ApplicationServices
import FlowCore
import FlowWindow

/// Real backend over the public Accessibility API (AXUIElement). No private API,
/// no synthesized mouse events: actions are AX actions or settable AX attributes.
@MainActor
public final class AXUIBackend: UIBackend {
    private var nextEpoch = 1
    /// AX elements per epoch. Only recent epochs are kept; older references become stale.
    private var store: [Int: (app: AppHandle, elements: [AXUIElement])] = [:]
    private let keptEpochs = 8
    private let frontmost: @MainActor () -> AppHandle?
    private let messagingTimeout: Float

    /// - Parameter frontmost: the frontmost app other than Flow itself
    ///   (FlowApp passes `AXWindowBackend.frontmostApp`).
    public init(messagingTimeout: Float = 0.75, frontmost: @escaping @MainActor () -> AppHandle?) {
        self.messagingTimeout = messagingTimeout
        self.frontmost = frontmost
    }

    public func isAccessibilityTrusted() -> Bool { AccessibilityPermission.isTrusted }

    // MARK: Apps

    public func resolveApp(_ scope: AppScope) throws(NavigationError) -> AppHandle {
        switch scope {
        case .frontmost:
            guard let app = frontmost() else { throw .noFrontmostApp }
            return app
        case .pid(let pid):
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                throw .appNotFound("pid \(pid)")
            }
            return Self.handle(app)
        case .named(let name):
            let key = LabelText.words(name)
            let match = NSWorkspace.shared.runningApplications.first { app in
                guard !app.isTerminated, app.activationPolicy == .regular else { return false }
                return LabelText.words(app.localizedName ?? "") == key
                    || app.bundleIdentifier?.caseInsensitiveCompare(name) == .orderedSame
            }
            guard let match else { throw .appNotFound(name) }
            return Self.handle(match)
        }
    }

    public func bringToFront(_ app: AppHandle) async -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid { return true }
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return false }
        if let url = running.bundleURL, !app.bundleID.isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in continuation.resume() }
            }
        } else {
            // Unbundled processes (test fixtures): ask politely; macOS may decline.
            if NSApp?.isActive == true { NSApp.yieldActivation(to: running) }
            _ = running.activate()
        }
        for _ in 0..<40 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid
    }

    nonisolated static func handle(_ app: NSRunningApplication) -> AppHandle {
        AppHandle(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "",
                  name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)")
    }

    // MARK: Inspection

    public func snapshot(of app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot {
        try capture(app, limits, retain: true)
    }

    public func observe(_ app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot {
        try capture(app, limits, retain: false)
    }

    private func capture(_ app: AppHandle, _ limits: SnapshotLimits, retain: Bool) throws(NavigationError) -> UISnapshot {
        let root = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(root, messagingTimeout)

        var windowValue: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &windowValue)
        if error == .apiDisabled { throw .accessibilityNotTrusted }
        if error != .success || windowValue == nil {
            error = AXUIElementCopyAttributeValue(root, kAXMainWindowAttribute as CFString, &windowValue)
        }
        if error == .apiDisabled { throw .accessibilityNotTrusted }
        guard error == .success, let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            throw error == .cannotComplete || error == .notImplemented ? .inaccessibleApp(app.name) : .noWindow(app.name)
        }
        let window = windowValue as! AXUIElement

        let epoch = retain ? nextEpoch : -1
        if retain { nextEpoch += 1 }
        var infos: [UIElementInfo] = []
        var elements: [AXUIElement] = []
        var truncated = false
        let deadline = ContinuousClock.now + limits.timeBudget
        let windowFrame = Self.frame(window)
        let screens = Self.screenFrames()

        func visit(_ element: AXUIElement, parent: Int?, depth: Int, clip: CGRect) {
            guard infos.count < limits.maxElements, depth <= limits.maxDepth, ContinuousClock.now < deadline else {
                truncated = true
                return
            }
            let index = infos.count
            let id = ElementID(epoch: epoch, index: index)
            let frame = Self.frame(element)
            let visible = frame.width >= 1 && frame.height >= 1 && frame.intersects(clip)
                && screens.contains { $0.intersects(frame) }
            let info = Self.read(element, id: id, parent: parent, frame: frame, visible: visible)
            infos.append(info)
            elements.append(element)
            let childClip = info.role == "AXScrollArea" ? clip.intersection(frame) : clip
            for child in Self.children(element) {
                visit(child, parent: index, depth: depth + 1, clip: childClip)
            }
        }
        visit(window, parent: nil, depth: 0, clip: windowFrame)

        // Unlabeled scroll areas borrow their content's label ("Sidebar" outline).
        for (i, info) in infos.enumerated() where info.kind == .scrollArea && info.label.isEmpty {
            if let content = infos[(i + 1)...].prefix(3).first(where: { $0.parentIndex == i && ($0.title ?? $0.descriptionText) != nil }) {
                infos[i] = info.with(inheritedLabel: content.title ?? content.descriptionText!)
            }
        }
        // Rows/cells/buttons without their own label borrow the first descendant text.
        for (i, info) in infos.enumerated() where info.label.isEmpty && Self.inheritsLabel(info.kind) {
            if let text = infos[(i + 1)...].prefix(12).first(where: {
                $0.kind == .staticText && !$0.label.isEmpty && Self.descends($0, from: i, in: infos)
            })?.label {
                infos[i] = info.with(inheritedLabel: text)
            }
        }

        if retain {
            store[epoch] = (app, elements)
            store.keys.filter { $0 <= epoch - keptEpochs }.forEach { store[$0] = nil }
        }
        let title = Self.string(window, kAXTitleAttribute) ?? ""
        return UISnapshot(epoch: epoch, app: app, windowTitle: title, windowFrame: windowFrame,
                          elements: infos, truncated: truncated)
    }

    public func refresh(_ id: ElementID) throws(NavigationError) -> UIElementInfo {
        let element = try lookup(id)
        var role: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard error == .success else {
            if error == .apiDisabled { throw .accessibilityNotTrusted }
            throw .targetGone
        }
        // Also gone if it was detached from its window (removed views can linger briefly).
        // Only an invalid-element error counts: some SwiftUI elements don't support AXWindow.
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .invalidUIElement {
            throw .targetGone
        }
        let frame = Self.frame(element)
        var info = Self.read(element, id: id, parent: nil, frame: frame,
                             visible: frame.width >= 1 && frame.height >= 1)
        if info.label.isEmpty, info.kind == .scrollArea,
            let content = Self.children(element).first(where: { Self.string($0, kAXTitleAttribute) ?? Self.string($0, kAXDescriptionAttribute) != nil })
        {
            info = info.with(inheritedLabel: Self.string(content, kAXTitleAttribute) ?? Self.string(content, kAXDescriptionAttribute)!)
        } else if info.label.isEmpty, Self.inheritsLabel(info.kind), let text = Self.firstDescendantText(element) {
            info = info.with(inheritedLabel: text)
        }
        return info
    }

    // MARK: Actions

    public func press(_ id: ElementID) throws(NavigationError) {
        let element = try lookup(id)
        try check(AXUIElementPerformAction(element, kAXPressAction as CFString), "pressing")
    }

    public func setFocused(_ id: ElementID) throws(NavigationError) {
        let element = try lookup(id)
        try check(AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue), "focusing")
    }

    public func setSelected(_ id: ElementID) throws(NavigationError) {
        let element = try lookup(id)
        try check(AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue), "selecting")
    }

    public func scroll(_ id: ElementID, _ direction: ScrollDirection) throws(NavigationError) {
        let element = try lookup(id)
        switch direction {
        case .up, .down:
            try page(element, down: direction == .down)
        case .top, .bottom:
            // Prefer the scroll bar's settable value; otherwise page repeatedly (bounded).
            if let bar = Self.verticalScrollBar(element), Self.isSettable(bar, kAXValueAttribute) {
                let value = NSNumber(value: direction == .top ? 0.0 : 1.0)
                try check(AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, value), "scrolling")
            } else {
                for _ in 0..<50 {
                    let before = scrollPosition(id)
                    try page(element, down: direction == .bottom)
                    if scrollPosition(id) == before { break }
                }
            }
        }
    }

    /// One page up/down. Order: the scroll area's own AXScroll…ByPage action; else set the
    /// vertical scroll bar's value by one page (page size from the thumb/track ratio); else
    /// press the scroll bar's page part. Some views list AXScroll…ByPage but refuse it
    /// (AppKit NSScrollView returns kAXErrorActionUnsupported).
    private func page(_ scrollArea: AXUIElement, down: Bool) throws(NavigationError) {
        let action = down ? "AXScrollDownByPage" : "AXScrollUpByPage"
        let direct = AXUIElementPerformAction(scrollArea, action as CFString)
        if direct == .success { return }
        if direct == .apiDisabled { throw .accessibilityNotTrusted }
        guard let bar = Self.verticalScrollBar(scrollArea) else {
            try check(direct, "scrolling")
            return
        }
        if Self.isSettable(bar, kAXValueAttribute),
            let current = (Self.attribute(bar, kAXValueAttribute) as? NSNumber)?.doubleValue
        {
            let step = Self.pageStep(bar)
            let next = min(1, max(0, current + (down ? step : -step)))
            try check(AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: next)), "scrolling")
            return
        }
        let part = down ? "AXIncrementPage" : "AXDecrementPage"
        guard let button = Self.children(bar).first(where: { Self.string($0, kAXSubroleAttribute) == part }) else {
            throw .notScrollable("This scroll area")
        }
        try check(AXUIElementPerformAction(button, kAXPressAction as CFString), "scrolling")
    }

    /// One page in scroll-bar value units: visible fraction f = thumb/track, page = f/(1-f),
    /// with 10% overlap so the user keeps context. Falls back to 0.2.
    static func pageStep(_ bar: AXUIElement) -> Double {
        let track = frame(bar)
        guard let thumb = children(bar).first(where: { string($0, kAXRoleAttribute) == "AXValueIndicator" }).map(frame),
            track.height > 0, thumb.height > 0, thumb.height < track.height
        else { return 0.2 }
        let fraction = Double(thumb.height / track.height)
        return min(1, max(0.02, fraction / (1 - fraction) * 0.9))
    }

    public func scrollPosition(_ id: ElementID) -> ScrollPosition? {
        guard let element = try? lookup(id) else { return nil }
        let vertical = Self.verticalScrollBar(element).flatMap { (Self.attribute($0, kAXValueAttribute) as? NSNumber)?.doubleValue }
        let marker = Self.children(element).prefix(4).map(Self.frame)
        return ScrollPosition(vertical: vertical, contentMarker: Array(marker))
    }

    public func isFocusedElement(_ id: ElementID, in app: AppHandle) -> Bool {
        guard let element = try? lookup(id) else { return false }
        let root = AXUIElementCreateApplication(app.pid)
        guard let focused = Self.attribute(root, kAXFocusedUIElementAttribute),
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let focusedElement = focused as! AXUIElement
        if CFEqual(focusedElement, element) { return true }
        // Text fields often focus an inner field editor; accept a focused descendant.
        var parent = Self.attribute(focusedElement, kAXParentAttribute)
        for _ in 0..<4 {
            guard let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { return false }
            if CFEqual(p as! AXUIElement, element) { return true }
            parent = Self.attribute(p as! AXUIElement, kAXParentAttribute)
        }
        return false
    }

    // MARK: Helpers

    private func lookup(_ id: ElementID) throws(NavigationError) -> AXUIElement {
        guard let entry = store[id.epoch], entry.elements.indices.contains(id.index) else { throw .targetGone }
        return entry.elements[id.index]
    }

    private func check(_ error: AXError, _ operation: String) throws(NavigationError) {
        switch error {
        case .success: return
        case .apiDisabled: throw .accessibilityNotTrusted
        case .invalidUIElement: throw .targetGone
        default: throw .axFailure(operation: operation, code: error.rawValue)
        }
    }

    static func read(_ e: AXUIElement, id: ElementID, parent: Int?, frame: CGRect, visible: Bool) -> UIElementInfo {
        let role = string(e, kAXRoleAttribute) ?? "AXUnknown"
        let subrole = string(e, kAXSubroleAttribute)
        let secure = subrole == "AXSecureTextField"
        var actionNames: CFArray?
        AXUIElementCopyActionNames(e, &actionNames)
        let titleElementLabel: String? = attribute(e, kAXTitleUIElementAttribute).flatMap { v in
            CFGetTypeID(v) == AXUIElementGetTypeID() ? string(v as! AXUIElement, kAXValueAttribute) : nil
        }
        return UIElementInfo(
            id: id, role: role, subrole: subrole,
            title: string(e, kAXTitleAttribute),
            descriptionText: string(e, kAXDescriptionAttribute),
            value: secure ? nil : valueString(e),
            placeholder: string(e, kAXPlaceholderValueAttribute),
            help: string(e, kAXHelpAttribute),
            identifier: string(e, kAXIdentifierAttribute),
            inheritedLabel: titleElementLabel,
            isEnabled: (attribute(e, kAXEnabledAttribute) as? Bool) ?? true,
            isFocused: (attribute(e, kAXFocusedAttribute) as? Bool) ?? false,
            isSelected: attribute(e, kAXSelectedAttribute) as? Bool,
            frame: frame,
            actions: (actionNames as? [String]) ?? [],
            canFocus: isSettable(e, kAXFocusedAttribute),
            canSelect: (role == "AXRow" || role == "AXCell" || role == "AXRadioButton") && isSettable(e, kAXSelectedAttribute),
            isVisible: visible, isSecure: secure, parentIndex: parent)
    }

    static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? {
        (attribute(e, name) as? String).map(LabelText.clean).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func valueString(_ e: AXUIElement) -> String? {
        switch attribute(e, kAXValueAttribute) {
        case let s as String: return s.isEmpty ? nil : String(LabelText.clean(s).prefix(200))
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func isSettable(_ e: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(e, name as CFString, &settable) == .success && settable.boolValue
    }

    static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func frame(_ e: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let v = attribute(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &origin)
        }
        if let v = attribute(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    static func verticalScrollBar(_ e: AXUIElement) -> AXUIElement? {
        guard let v = attribute(e, kAXVerticalScrollBarAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func firstDescendantText(_ e: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        for child in children(e) {
            if string(child, kAXRoleAttribute) == "AXStaticText", let v = valueString(child) ?? string(child, kAXTitleAttribute) {
                return v
            }
            if let found = firstDescendantText(child, depth: depth + 1) { return found }
        }
        return nil
    }

    static func inheritsLabel(_ kind: ElementKind) -> Bool {
        [.row, .cell, .button, .link, .radio, .tab, .menuButton, .checkbox].contains(kind)
    }

    static func descends(_ e: UIElementInfo, from ancestor: Int, in infos: [UIElementInfo]) -> Bool {
        var current = e.parentIndex
        while let i = current {
            if i == ancestor { return true }
            current = infos[i].parentIndex
        }
        return false
    }

    /// Screen frames in AX coordinates (top-left origin of the primary display).
    static func screenFrames() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { s in
            CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
    }
}

extension UIElementInfo {
    func with(inheritedLabel: String) -> UIElementInfo {
        UIElementInfo(
            id: id, role: role, subrole: subrole, title: title, descriptionText: descriptionText, value: value,
            placeholder: placeholder, help: help, identifier: identifier, inheritedLabel: inheritedLabel,
            isEnabled: isEnabled, isFocused: isFocused, isSelected: isSelected, frame: frame, actions: actions,
            canFocus: canFocus, canSelect: canSelect, isVisible: isVisible, isSecure: isSecure, parentIndex: parentIndex)
    }
}
