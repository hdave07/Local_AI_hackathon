import CoreGraphics
import FlowCore

/// Deterministic geometry (spec 02 §7): frames are computed in code, never by the model.
public enum WindowGeometry {
    public static let defaultStep = CGSize(width: 120, height: 100)
    public static let minimumSize = CGSize(width: 240, height: 160)

    public static func targetFrame(for position: WindowPosition, current: CGRect, screen: CGRect) -> CGRect {
        let half = (screen.width / 2).rounded(.down)
        switch position {
        case .leftHalf:
            return CGRect(x: screen.minX, y: screen.minY, width: half, height: screen.height)
        case .rightHalf:
            return CGRect(x: screen.minX + half, y: screen.minY, width: screen.width - half, height: screen.height)
        case .maximize:
            return screen
        case .center:
            let size = CGSize(width: min(current.width, screen.width), height: min(current.height, screen.height))
            return CGRect(
                x: (screen.midX - size.width / 2).rounded(.down),
                y: (screen.midY - size.height / 2).rounded(.down),
                width: size.width, height: size.height)
        }
    }

    /// Relative resize by a fixed step, kept on screen and above a minimum size.
    public static func resized(
        _ current: CGRect, change: ResizeChange, screen: CGRect,
        step: CGSize = defaultStep, minimum: CGSize = minimumSize
    ) -> CGRect {
        var dw: CGFloat = 0, dh: CGFloat = 0
        switch change {
        case .wider: dw = step.width
        case .narrower: dw = -step.width
        case .taller: dh = step.height
        case .shorter: dh = -step.height
        case .larger: dw = step.width; dh = step.height
        case .smaller: dw = -step.width; dh = -step.height
        }
        let width = clamp(current.width + dw, min(minimum.width, current.width), screen.width)
        let height = clamp(current.height + dh, min(minimum.height, current.height), screen.height)
        var x = current.minX, y = current.minY
        if x + width > screen.maxX { x = screen.maxX - width }
        if y + height > screen.maxY { y = screen.maxY - height }
        return CGRect(x: max(x, screen.minX), y: max(y, screen.minY), width: width, height: height)
    }

    /// When an app enforces a minimum width larger than its half, shift the split so
    /// that window gets its observed minimum and the other side gets the remainder
    /// (spec 02 §7 "preserve minimum size"). Returns nil if no adjustment is needed or
    /// the two windows cannot fit side by side.
    public static func adjustedSplit(
        leftObserved: CGSize, rightObserved: CGSize, leftTarget: CGRect, rightTarget: CGRect,
        screen: CGRect, tolerance: CGFloat = 2
    ) -> (left: CGRect, right: CGRect)? {
        let leftTooWide = leftObserved.width > leftTarget.width + tolerance
        let rightTooWide = rightObserved.width > rightTarget.width + tolerance
        guard leftTooWide || rightTooWide else { return nil }
        let needed = (leftTooWide ? leftObserved.width : 0) + (rightTooWide ? rightObserved.width : 0)
        guard needed <= screen.width else { return nil }
        let leftWidth = rightTooWide ? screen.width - rightObserved.width : leftObserved.width
        return (
            CGRect(x: screen.minX, y: screen.minY, width: leftWidth, height: screen.height),
            CGRect(x: screen.minX + leftWidth, y: screen.minY, width: screen.width - leftWidth, height: screen.height)
        )
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Converts an AppKit `visibleFrame` (bottom-left origin) to AX coordinates (top-left origin).
    public static func axFrame(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(v, hi)) }
}
