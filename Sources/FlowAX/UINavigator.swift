import CoreGraphics
import FlowCore
import FlowWindow
import Foundation

/// Generic UI navigation (spec 02 §8, plan T-021). For every action:
/// inspect → resolve deterministically → (clarify if ambiguous) → revalidate the target
/// against live AX → act through AX → verify by re-observing → typed result.
@MainActor
public final class UINavigator {
    public struct Configuration: Sendable {
        /// Bring the target app forward before inspecting (needed when commands are typed
        /// into Flow's own window, which is then frontmost).
        public var bringTargetToFront = false
        public var settleTimeout: Duration = .milliseconds(1200)
        public var pollInterval: Duration = .milliseconds(80)
        public var numbersLifetime: Duration = .seconds(60)
        public var maxNumbers = 40
        public var frameTolerance: CGFloat = 2
        public var limits = SnapshotLimits()
        /// Refuse to press controls whose label sounds consequential (send, delete, …).
        /// Defence in depth behind the planner's confirmation flow (ADR 0004).
        public var refuseConsequentialControls = true

        public init() {}
    }

    struct ActiveNumbers {
        let app: AppHandle
        let epoch: Int
        let targets: [NumberedTarget]
        let layout: [String]
        let intent: NavigationIntent
        let createdAt: ContinuousClock.Instant
    }

    public let backend: UIBackend
    public let configuration: Configuration
    private let overlay: OverlayPresenting?
    private(set) var activeNumbers: ActiveNumbers?

    public init(backend: UIBackend, overlay: OverlayPresenting? = nil, configuration: Configuration = Configuration()) {
        self.backend = backend
        self.overlay = overlay
        self.configuration = configuration
    }

    /// Numbers currently offered to the user, if any.
    public var currentNumbers: [NumberedTarget] { activeNumbers?.targets ?? [] }

    public func perform(_ command: NavCommand) async -> NavigationResult {
        guard backend.isAccessibilityTrusted() else { return failure(command, .accessibilityNotTrusted) }
        do throws(NavigationError) {
            switch command {
            case .click(let reference, let scope):
                return try await act(.click, reference, scope, command)
            case .focus(let reference, let scope):
                return try await act(.focus, reference, scope, command)
            case .scroll(let reference, let direction, let scope):
                return try await scroll(reference, direction, scope, command)
            case .showNumbers(let reference, let scope):
                return try await showNumbers(reference, scope, command)
            case .choose(let number):
                return try await choose(number, command)
            case .hideNumbers:
                clearNumbers()
                return result(command, .completed, message: "Numbers hidden.")
            case .inspect(let scope):
                let (app, snapshot) = try await prepare(scope, requireContent: false)
                let actionable = snapshot.actionable
                return result(command, .completed, app: app,
                              evidence: ["window “\(snapshot.windowTitle)”: \(snapshot.elements.count) elements, \(actionable.count) actionable\(snapshot.truncated ? " (truncated)" : "")"]
                                  + actionable.prefix(60).map { "\($0.id) \($0.displayName) \($0.frame.compactDescription)" },
                              message: "Inspected \(app.name).")
            }
        } catch {
            if error == .staleNumbers || error == .noActiveNumbers { clearNumbers() }
            return failure(command, error)
        }
    }

    /// Planner/executor entry point: act on an element from an earlier snapshot.
    /// The element is always revalidated against live AX first.
    public func perform(_ intent: NavigationIntent, on element: UIElementInfo, in app: AppHandle) async -> NavigationResult {
        let command = NavCommand.click(TargetReference.parse(element.label), .pid(app.pid))
        guard backend.isAccessibilityTrusted() else { return failure(command, .accessibilityNotTrusted) }
        do throws(NavigationError) {
            return try await execute(intent, element, app: app, command: command)
        } catch {
            return failure(command, error)
        }
    }

    // MARK: Commands

    private func act(_ intent: NavigationIntent, _ reference: TargetReference, _ scope: AppScope, _ command: NavCommand)
        async throws(NavigationError) -> NavigationResult
    {
        let (app, snapshot) = try await prepare(scope, requireContent: false)
        switch TargetResolver.resolve(reference, intent: intent, in: snapshot) {
        case .unique(let element):
            return try await execute(intent, element, app: app, command: command)
        case .ambiguous(let matches):
            let identical = Set(matches.map { "\($0.kind)|\($0.label)" }).count == 1
            let prompt = identical
                ? "There are \(matches.count) identical \(matches[0].displayName)s. Which one? Say a number."
                : "\(matches.count) controls match “\(reference.raw)”. Which one? Say a number."
            return clarify(command, intent, app, snapshot, matches, prompt: prompt)
        case .lowConfidence(let matches):
            let prompt = matches.count == 1
                ? "Did you mean \(matches[0].displayName)? Say 1 to confirm."
                : "I'm not sure which control you mean. Say a number."
            return clarify(command, intent, app, snapshot, matches, prompt: prompt)
        case .notFound:
            if Self.contentActionable(snapshot).isEmpty { throw .inaccessibleApp(app.name) }
            throw .notFound(reference.raw)
        }
    }

    private func scroll(_ reference: TargetReference?, _ direction: ScrollDirection, _ scope: AppScope, _ command: NavCommand)
        async throws(NavigationError) -> NavigationResult
    {
        let intent = NavigationIntent.scroll(direction)
        if let reference { return try await act(intent, reference, scope, command) }
        let (app, snapshot) = try await prepare(scope, requireContent: false)
        let areas = TargetResolver.candidates(for: intent, in: snapshot)
        guard !areas.isEmpty else { throw .notScrollable("This window") }
        // Predictable default for low-risk geometry (D-013): the largest visible scroll area.
        func visibleArea(_ e: UIElementInfo) -> CGFloat {
            let r = e.frame.intersection(snapshot.windowFrame)
            return r.isNull ? 0 : r.width * r.height
        }
        let ranked = areas.sorted { visibleArea($0) > visibleArea($1) }
        if ranked.count > 1, visibleArea(ranked[0]) == visibleArea(ranked[1]) {
            return clarify(command, intent, app, snapshot, ranked, prompt: "Which area should I scroll? Say a number.")
        }
        return try await execute(intent, ranked[0], app: app, command: command)
    }

    private func showNumbers(_ reference: TargetReference?, _ scope: AppScope, _ command: NavCommand)
        async throws(NavigationError) -> NavigationResult
    {
        let (app, snapshot) = try await prepare(scope, requireContent: true)
        var targets: [UIElementInfo]
        if let reference {
            switch TargetResolver.resolve(reference, intent: .click, in: snapshot) {
            case .unique(let e): targets = [e]
            case .ambiguous(let es), .lowConfidence(let es): targets = es
            case .notFound: throw .notFound(reference.raw)
            }
        } else {
            targets = TargetResolver.removeContainers(snapshot.actionable, in: snapshot).sorted(by: TargetResolver.readingOrder)
        }
        let shown = number(app, snapshot, Array(targets.prefix(configuration.maxNumbers)), intent: .click)
        let more = targets.count > shown.count ? " (first \(shown.count) of \(targets.count))" : ""
        return result(
            command, .completed, app: app,
            clarification: Clarification(prompt: "Say a number.", options: shown, epoch: snapshot.epoch, intent: .click),
            evidence: shown.map { "\($0.number): \($0.element.displayName) \($0.element.frame.compactDescription)" },
            message: "Showing \(shown.count) numbered targets in \(app.name)\(more).")
    }

    private func choose(_ number: Int, _ command: NavCommand) async throws(NavigationError) -> NavigationResult {
        guard let active = activeNumbers else { throw .noActiveNumbers }
        if ContinuousClock.now - active.createdAt > configuration.numbersLifetime { throw .staleNumbers }
        guard (1...active.targets.count).contains(number) else {
            throw .numberOutOfRange(number, count: active.targets.count)
        }
        if configuration.bringTargetToFront { _ = await backend.bringToFront(active.app) }
        // Numbers belong to one layout; any layout change invalidates all of them (NAV-03).
        let current = try backend.observe(active.app, limits: configuration.limits)
        guard current.layoutSignature == active.layout else { throw .staleNumbers }
        let target = active.targets[number - 1].element
        clearNumbers()
        return try await execute(active.intent, target, app: active.app, command: command)
    }

    // MARK: Execution

    private func execute(_ intent: NavigationIntent, _ target: UIElementInfo, app: AppHandle, command: NavCommand)
        async throws(NavigationError) -> NavigationResult
    {
        let fresh = try revalidate(target)
        var evidence = ["revalidated \(fresh.displayName) at \(fresh.frame.compactDescription)"]

        // Clicking a text field means putting the cursor in it.
        let intent = (intent == .click && fresh.kind == .textInput && !fresh.canPress && fresh.canFocus) ? .focus : intent

        switch intent {
        case .click:
            if configuration.refuseConsequentialControls, Self.isConsequential(fresh.label) {
                throw .consequentialControl(fresh.displayName)
            }
            if fresh.canPress {
                let before = try backend.observe(app, limits: configuration.limits)
                try backend.press(fresh.id)
                var after: UISnapshot?
                var windowGone = false
                let changed = await waitUntil {
                    do throws(NavigationError) {
                        after = try backend.observe(app, limits: configuration.limits)
                    } catch {
                        windowGone = true
                        return true
                    }
                    return after!.contentSignature != before.contentSignature
                        || after!.layoutSignature != before.layoutSignature
                        || after!.windowTitle != before.windowTitle
                }
                guard changed else {
                    return result(command, .unverified, app: app, target: fresh, evidence: evidence + ["no visible change within \(configuration.settleTimeout)"],
                                  message: "Pressed \(fresh.displayName), but I couldn't see any change.")
                }
                evidence += windowGone ? ["window closed or changed"] : Self.describeChanges(from: before, to: after!)
                return result(command, .completed, app: app, target: fresh, evidence: evidence, message: "Clicked \(fresh.displayName).")
            }
            if fresh.canSelect {
                try backend.setSelected(fresh.id)
                let selected = await waitUntil { (try? backend.refresh(fresh.id))?.isSelected == true }
                return result(command, selected ? .completed : .failed, app: app, target: fresh,
                              evidence: evidence + ["AXSelected re-read: \(selected)"],
                              message: selected ? "Selected \(fresh.displayName)." : "macOS didn't confirm \(fresh.displayName) was selected.")
            }
            throw .notPressable(fresh.displayName)

        case .focus:
            guard fresh.canFocus else { throw .notFocusable(fresh.displayName) }
            try backend.setFocused(fresh.id)
            let focused = await waitUntil { backend.isFocusedElement(fresh.id, in: app) }
            return result(command, focused ? .completed : .failed, app: app, target: fresh,
                          evidence: evidence + ["focused element re-read matches target: \(focused)"],
                          message: focused ? "Focused \(fresh.displayName)." : "macOS didn't move focus to \(fresh.displayName).")

        case .scroll(let direction):
            guard fresh.isScrollable else { throw .notScrollable(fresh.displayName) }
            let before = backend.scrollPosition(fresh.id)
            if let v = before?.vertical {
                if (direction == .down || direction == .bottom) && v >= 0.999 { throw .atScrollLimit("bottom") }
                if (direction == .up || direction == .top) && v <= 0.001 { throw .atScrollLimit("top") }
            }
            try backend.scroll(fresh.id, direction)
            var after: ScrollPosition?
            let towardEnd = direction == .down || direction == .bottom
            _ = await waitUntil {
                after = backend.scrollPosition(fresh.id)
                return Self.scrollMovement(from: before, to: after) != nil
            }
            evidence.append("scroll position \(Self.describe(before)) → \(Self.describe(after))")
            switch Self.scrollMovement(from: before, to: after) {
            case towardEnd?:
                return result(command, .completed, app: app, target: fresh, evidence: evidence,
                              message: "Scrolled \(fresh.displayName) \(direction.rawValue).")
            case (!towardEnd)?:
                return result(command, .failed, app: app, target: fresh, evidence: evidence + ["moved the opposite way"],
                              message: "\(fresh.displayName) scrolled the wrong way.")
            default:
                return result(command, .unverified, app: app, target: fresh, evidence: evidence,
                              message: "Asked \(fresh.displayName) to scroll, but its position didn't change.")
            }
        }
    }

    static let consequentialWords: Set<String> = ["send", "delete", "discard", "trash", "erase"]

    /// Whether a label names a consequential action ("Send", "Move to Trash", "Delete Draft").
    static func isConsequential(_ label: String) -> Bool {
        !Set(LabelText.words(label)).isDisjoint(with: consequentialWords)
    }

    /// Spec 02 §3 "No stale AX identifiers": re-read the same element and refuse if it
    /// disappeared, changed identity, moved, or became disabled (NAV-05, ERR-02).
    func revalidate(_ target: UIElementInfo) throws(NavigationError) -> UIElementInfo {
        let fresh = try backend.refresh(target.id)
        if fresh.role != target.role || fresh.subrole != target.subrole { throw .targetChanged("it is now a different kind of control") }
        if fresh.label != target.label { throw .targetChanged("“\(target.label)” is now “\(fresh.label)”") }
        if fresh.identifier != target.identifier { throw .targetChanged("identifier changed") }
        let t = configuration.frameTolerance
        if abs(fresh.frame.minX - target.frame.minX) > t || abs(fresh.frame.minY - target.frame.minY) > t
            || abs(fresh.frame.width - target.frame.width) > t || abs(fresh.frame.height - target.frame.height) > t
        {
            throw .targetChanged("it moved from \(target.frame.compactDescription) to \(fresh.frame.compactDescription)")
        }
        if !fresh.isEnabled { throw .targetDisabled(fresh.displayName) }
        return fresh
    }

    // MARK: Helpers

    private func prepare(_ scope: AppScope, requireContent: Bool) async throws(NavigationError) -> (AppHandle, UISnapshot) {
        let app = try backend.resolveApp(scope)
        if configuration.bringTargetToFront { _ = await backend.bringToFront(app) }
        let snapshot = try backend.snapshot(of: app, limits: configuration.limits)
        if requireContent, Self.contentActionable(snapshot).isEmpty { throw .inaccessibleApp(app.name) }
        return (app, snapshot)
    }

    /// Actionable elements other than the window's own close/minimize/zoom buttons.
    static func contentActionable(_ snapshot: UISnapshot) -> [UIElementInfo] {
        snapshot.actionable.filter { UIElementInfo.subroleLabel($0.subrole) == nil }
    }

    private func clarify(_ command: NavCommand, _ intent: NavigationIntent, _ app: AppHandle, _ snapshot: UISnapshot,
                         _ matches: [UIElementInfo], prompt: String) -> NavigationResult {
        let numbered = number(app, snapshot, Array(matches.prefix(configuration.maxNumbers)), intent: intent)
        return result(
            command, .needsClarification, app: app,
            clarification: Clarification(prompt: prompt, options: numbered, epoch: snapshot.epoch, intent: intent),
            evidence: numbered.map { "\($0.number): \($0.element.displayName) \($0.element.frame.compactDescription)" },
            message: prompt)
    }

    private func number(_ app: AppHandle, _ snapshot: UISnapshot, _ elements: [UIElementInfo], intent: NavigationIntent) -> [NumberedTarget] {
        let numbered = elements.enumerated().map { NumberedTarget(number: $0.offset + 1, element: $0.element) }
        let createdAt = ContinuousClock.now
        activeNumbers = ActiveNumbers(app: app, epoch: snapshot.epoch, targets: numbered,
                                      layout: snapshot.layoutSignature, intent: intent, createdAt: createdAt)
        overlay?.show(numbered)
        let lifetime = configuration.numbersLifetime
        Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            if self?.activeNumbers?.createdAt == createdAt { self?.clearNumbers() }
        }
        return numbered
    }

    private func clearNumbers() {
        activeNumbers = nil
        overlay?.hide()
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + configuration.settleTimeout
        while true {
            if condition() { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    static func describeChanges(from before: UISnapshot, to after: UISnapshot) -> [String] {
        let old = Set(before.elements.filter { $0.isVisible && $0.kind == .staticText }.map(\.label))
        let new = after.elements.filter { $0.isVisible && $0.kind == .staticText && !$0.label.isEmpty && !old.contains($0.label) }
        let texts = new.prefix(3).map { "now shows “\($0.label)”" }
        if !texts.isEmpty { return texts }
        return before.layoutSignature != after.layoutSignature ? ["controls moved, appeared or disappeared"] : ["window content changed"]
    }

    /// true = moved toward the end (down), false = toward the start (up), nil = no movement.
    static func scrollMovement(from before: ScrollPosition?, to after: ScrollPosition?) -> Bool? {
        guard let before, let after, before != after else { return nil }
        if let b = before.vertical, let a = after.vertical {
            return abs(a - b) < 0.0005 ? nil : a > b
        }
        // Content moving up on screen means the view scrolled down.
        guard let b = before.contentMarker.first, let a = after.contentMarker.first, a.minY != b.minY else { return nil }
        return a.minY < b.minY
    }

    static func describe(_ p: ScrollPosition?) -> String {
        guard let p else { return "unknown" }
        if let v = p.vertical { return String(format: "%.3f", v) }
        return p.contentMarker.first.map { "content at y=\(Int($0.minY))" } ?? "unknown"
    }

    private func result(
        _ command: NavCommand, _ status: NavigationStatus, app: AppHandle? = nil, target: UIElementInfo? = nil,
        clarification: Clarification? = nil, error: NavigationError? = nil, evidence: [String] = [], message: String
    ) -> NavigationResult {
        NavigationResult(actionID: UUID(), command: command, status: status, app: app, target: target,
                         clarification: clarification, error: error, evidence: evidence, userMessage: message,
                         timestamp: Date())
    }

    private func failure(_ command: NavCommand, _ error: NavigationError) -> NavigationResult {
        result(command, error.isCapabilityLimit ? .unsupported : .failed, error: error, message: error.userMessage)
    }
}
