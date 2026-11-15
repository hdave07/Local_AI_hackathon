import CoreGraphics
import FlowWindow
import Foundation

/// Identifies one element inside one snapshot. Numbers and references are only
/// meaningful for the snapshot (`epoch`) they came from (spec 02 §8).
public struct ElementID: Hashable, Sendable, CustomStringConvertible {
    public let epoch: Int
    public let index: Int

    public init(epoch: Int, index: Int) {
        self.epoch = epoch
        self.index = index
    }

    public var description: String { "e\(epoch).\(index)" }
}

/// Which application to inspect.
public enum AppScope: Sendable, Equatable {
    /// The frontmost app other than Flow itself.
    case frontmost
    /// A running app by localized name or bundle identifier (case-insensitive).
    case named(String)
    /// A running app by process identifier (tests and fixtures).
    case pid(pid_t)
}

/// Coarse element categories derived from AX role/subrole.
public enum ElementKind: String, Sendable, Equatable, CaseIterable {
    case button, checkbox, radio, tab, link, menuButton, textInput, row, cell, slider
    case scrollArea, staticText, image, group, other
}

/// A read-only description of one AX element at snapshot time. Contains no
/// AXUIElement, so it is Sendable and safe to hand to other modules.
public struct UIElementInfo: Sendable, Equatable {
    public let id: ElementID
    public let role: String
    public let subrole: String?
    public let title: String?
    public let descriptionText: String?
    /// Value for non-secure elements only; never read from secure text fields.
    public let value: String?
    public let placeholder: String?
    public let help: String?
    public let identifier: String?
    /// Label borrowed from a linked title element or a descendant static text.
    public let inheritedLabel: String?
    public let isEnabled: Bool
    public let isFocused: Bool
    public let isSelected: Bool?
    public let frame: CGRect
    public let actions: [String]
    public let canFocus: Bool
    public let canSelect: Bool
    public let isVisible: Bool
    public let isSecure: Bool
    /// Index of the parent element in the same snapshot.
    public let parentIndex: Int?

    public init(
        id: ElementID, role: String, subrole: String? = nil, title: String? = nil, descriptionText: String? = nil,
        value: String? = nil, placeholder: String? = nil, help: String? = nil, identifier: String? = nil,
        inheritedLabel: String? = nil, isEnabled: Bool = true, isFocused: Bool = false, isSelected: Bool? = nil,
        frame: CGRect, actions: [String] = [], canFocus: Bool = false, canSelect: Bool = false,
        isVisible: Bool = true, isSecure: Bool = false, parentIndex: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.subrole = subrole
        self.title = title
        self.descriptionText = descriptionText
        self.value = isSecure ? nil : value
        self.placeholder = placeholder
        self.help = help
        self.identifier = identifier
        self.inheritedLabel = inheritedLabel
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.isSelected = isSelected
        self.frame = frame
        self.actions = actions
        self.canFocus = canFocus
        self.canSelect = canSelect
        self.isVisible = isVisible
        self.isSecure = isSecure
        self.parentIndex = parentIndex
    }

    public var kind: ElementKind {
        switch role {
        case "AXButton":
            return subrole == "AXTabButton" ? .tab : .button
        case "AXCheckBox", "AXSwitch", "AXToggle": return .checkbox
        case "AXRadioButton": return .radio
        case "AXLink": return .link
        case "AXMenuButton", "AXPopUpButton", "AXComboBox": return .menuButton
        case "AXTextField", "AXTextArea", "AXSearchField": return .textInput
        case "AXRow": return .row
        case "AXCell": return .cell
        case "AXSlider", "AXIncrementor": return .slider
        case "AXScrollArea": return .scrollArea
        case "AXStaticText": return .staticText
        case "AXImage": return .image
        case "AXGroup", "AXSplitGroup", "AXTabGroup", "AXToolbar", "AXLayoutArea": return .group
        default: return .other
        }
    }

    /// Best user-visible label, in priority order. Empty if the app exposes none.
    public var label: String {
        let candidates: [String?]
        switch kind {
        case .textInput:
            candidates = [title, descriptionText, inheritedLabel, placeholder]
        case .staticText:
            candidates = [value, title, descriptionText]
        default:
            candidates = [title, descriptionText, inheritedLabel, Self.subroleLabel(subrole)]
        }
        return candidates.lazy.compactMap { $0.map(LabelText.clean) }.first { !$0.isEmpty } ?? ""
    }

    public var canPress: Bool { actions.contains("AXPress") }

    public var isScrollable: Bool {
        kind == .scrollArea && actions.contains { $0.hasPrefix("AXScroll") && $0.hasSuffix("ByPage") }
    }

    /// Whether Flow can act on it at all (used for numbered targets).
    public var isActionable: Bool {
        guard isVisible, isEnabled else { return false }
        if Self.scrollBarParts.contains(subrole ?? "") { return false }
        return canPress || canSelect || (kind == .textInput && canFocus) || isScrollable
    }

    /// Display text for clarifications and overlays.
    public var displayName: String {
        let name = label.isEmpty ? "unlabeled" : "“\(label)”"
        return "\(name) \(Self.kindName(kind))"
    }

    static let scrollBarParts: Set<String> = [
        "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage",
    ]

    static func subroleLabel(_ subrole: String?) -> String? {
        switch subrole {
        case "AXCloseButton": "Close"
        case "AXMinimizeButton": "Minimize"
        case "AXZoomButton": "Zoom"
        case "AXFullScreenButton": "Full Screen"
        default: nil
        }
    }

    static func kindName(_ kind: ElementKind) -> String {
        switch kind {
        case .button: "button"
        case .checkbox: "checkbox"
        case .radio: "option"
        case .tab: "tab"
        case .link: "link"
        case .menuButton: "menu"
        case .textInput: "field"
        case .row: "row"
        case .cell: "cell"
        case .slider: "slider"
        case .scrollArea: "scroll area"
        case .staticText: "text"
        case .image: "image"
        case .group: "group"
        case .other: "element"
        }
    }
}

/// All visible structure of one window of one app at one moment.
public struct UISnapshot: Sendable, Equatable {
    public let epoch: Int
    public let app: AppHandle
    public let windowTitle: String
    public let windowFrame: CGRect
    public let elements: [UIElementInfo]
    /// True if inspection stopped at a size, depth or time limit.
    public let truncated: Bool

    public init(epoch: Int, app: AppHandle, windowTitle: String, windowFrame: CGRect,
                elements: [UIElementInfo], truncated: Bool = false) {
        self.epoch = epoch
        self.app = app
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.elements = elements
        self.truncated = truncated
    }

    public func element(_ id: ElementID) -> UIElementInfo? {
        guard id.epoch == epoch, elements.indices.contains(id.index) else { return nil }
        return elements[id.index]
    }

    public var actionable: [UIElementInfo] { elements.filter(\.isActionable) }

    /// Layout identity of the actionable elements: role, label and position (4 pt grid).
    /// Text content changes (a clock, a result display) do not alter it.
    public var layoutSignature: [String] {
        actionable.map { e in
            "\(e.role)|\(e.subrole ?? "")|\(e.label)|\(Int(e.frame.minX / 4)),\(Int(e.frame.minY / 4)),\(Int(e.frame.width / 4)),\(Int(e.frame.height / 4))"
        }
    }

    /// Visible content: used to detect that an action had an observable effect.
    public var contentSignature: [String] {
        elements.filter(\.isVisible).map { e in
            "\(e.role)|\(e.label)|\(e.value ?? "")|\(e.isFocused)|\(e.isSelected.map(String.init) ?? "")|\(e.isEnabled)"
        }
    }

    /// Whether `ancestor` is an ancestor of `element` in this snapshot.
    public func isAncestor(_ ancestor: ElementID, of element: ElementID) -> Bool {
        var current = self.element(element)?.parentIndex
        while let index = current {
            if index == ancestor.index { return true }
            current = elements[index].parentIndex
        }
        return false
    }
}

public struct SnapshotLimits: Sendable {
    public var maxElements = 2_000
    public var maxDepth = 40
    public var timeBudget: Duration = .seconds(2)

    public init() {}
}

/// Label normalization shared by snapshots and the resolver.
public enum LabelText {
    /// Removes bidi control marks and surrounding whitespace (Calculator wraps values in U+200E).
    public static func clean(_ s: String) -> String {
        let bidi: Set<Character> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        return String(s.filter { !bidi.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased, diacritic-folded words with punctuation removed.
    public static func words(_ s: String) -> [String] {
        clean(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
