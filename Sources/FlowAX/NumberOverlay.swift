import AppKit
import FlowWindow

/// Shows numbered targets on screen. Implementations must not take focus or clicks.
@MainActor
public protocol OverlayPresenting: AnyObject {
    func show(_ targets: [NumberedTarget])
    func hide()
}

/// Converts AX frames (top-left origin of the primary display) to AppKit screen
/// coordinates (bottom-left origin).
public enum OverlayGeometry {
    public static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Badge placed at the element's top-left corner, kept inside `bounds`.
    public static func badgeRect(for element: CGRect, size: CGSize, within bounds: CGRect) -> CGRect {
        var origin = CGPoint(x: element.minX - size.width / 3, y: element.maxY - size.height * 2 / 3)
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}

/// Transparent, click-through, non-activating panel over the primary display with one
/// outlined, numbered badge per target. Badges are accessibility elements labelled
/// "<n>: <target>", so the mapping is inspectable through AX as well as visible.
@MainActor
public final class ScreenOverlay: OverlayPresenting {
    private var panel: NSPanel?

    public init() {}

    public func show(_ targets: [NumberedTarget]) {
        hide()
        guard let screen = NSScreen.screens.first, !targets.isEmpty else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Flow numbers"
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        root.setAccessibilityLabel("Flow numbered targets")
        for target in targets {
            let frame = OverlayGeometry.appKitRect(fromAX: target.element.frame, primaryScreenHeight: screen.frame.height)
                .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            let outline = OutlineView(frame: frame.insetBy(dx: -2, dy: -2))
            root.addSubview(outline)

            let text = "\(target.number)"
            let size = CGSize(width: max(22, CGFloat(text.count) * 10 + 12), height: 22)
            let badge = BadgeView(frame: OverlayGeometry.badgeRect(for: frame, size: size, within: root.bounds), text: text)
            badge.setAccessibilityElement(true)
            badge.setAccessibilityRole(.staticText)
            badge.setAccessibilityLabel("\(target.number): \(target.element.displayName)")
            root.addSubview(badge)
        }
        panel.contentView = root
        panel.orderFrontRegardless()
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private final class OutlineView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemOrange.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.stroke()
        }
    }

    private final class BadgeView: NSView {
        let text: String
        init(frame: NSRect, text: String) {
            self.text = text
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                    withAttributes: attributes)
        }
    }
}
