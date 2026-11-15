import CoreGraphics

/// Where the floating HUD goes (ADR 0011). Pure geometry in AppKit screen coordinates
/// (origin bottom-left of the primary display), so it is unit-testable without a display.
public enum HUDPlacement {
    public enum Corner: String, Sendable, CaseIterable { case topRight, topLeft, bottomRight, bottomLeft }

    public static let margin: CGFloat = 16

    /// - Parameters:
    ///   - size: the HUD's current size.
    ///   - screens: visible frames (menu bar and Dock excluded), primary display first.
    ///   - saved: the origin the user dragged the HUD to, if any.
    /// - Returns: a frame entirely inside one screen's visible frame.
    public static func frame(size: CGSize, screens: [CGRect], saved: CGPoint?, corner: Corner = .topRight) -> CGRect {
        guard let primary = screens.first else { return CGRect(origin: saved ?? .zero, size: size) }
        if let saved {
            let center = CGPoint(x: saved.x + size.width / 2, y: saved.y + size.height / 2)
            // Keep it on the display it was dragged to; if that display is gone, use the nearest one.
            let screen = screens.first { $0.contains(center) } ?? nearest(to: center, in: screens) ?? primary
            return clamp(CGRect(origin: saved, size: size), to: screen)
        }
        return clamp(CGRect(origin: defaultOrigin(size: size, in: primary, corner: corner), size: size), to: primary)
    }

    /// Keeps `rect` fully inside `bounds` (shrinking only if it cannot fit).
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let w = min(rect.width, bounds.width), h = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - w)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// When the HUD grows or shrinks, keep its top edge where it was (it hangs from the top).
    public static func resized(_ frame: CGRect, to size: CGSize, screens: [CGRect]) -> CGRect {
        let origin = CGPoint(x: frame.minX, y: frame.maxY - size.height)
        return Self.frame(size: size, screens: screens, saved: origin)
    }

    static func defaultOrigin(size: CGSize, in screen: CGRect, corner: Corner) -> CGPoint {
        switch corner {
        case .topRight: CGPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
        case .topLeft: CGPoint(x: screen.minX + margin, y: screen.maxY - size.height - margin)
        case .bottomRight: CGPoint(x: screen.maxX - size.width - margin, y: screen.minY + margin)
        case .bottomLeft: CGPoint(x: screen.minX + margin, y: screen.minY + margin)
        }
    }

    static func nearest(to point: CGPoint, in screens: [CGRect]) -> CGRect? {
        screens.min { distance(point, $0) < distance(point, $1) }
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Fraction of `screen` the HUD covers (it must not obscure large parts of the active app).
    public static func coverage(_ frame: CGRect, of screen: CGRect) -> CGFloat {
        let i = frame.intersection(screen)
        guard !i.isNull, screen.width > 0, screen.height > 0 else { return 0 }
        return (i.width * i.height) / (screen.width * screen.height)
    }
}
