import SwiftUI

/// Flow's design tokens: white rice, dark ink, one blush pink, frosted panels.
/// Keep every color in the HUD coming from here so the palette stays minimal.
enum FlowTheme {
    // Colors
    static let ink = Color(red: 0x33 / 255, green: 0x30 / 255, blue: 0x3F / 255)          // #33303f
    static let inkSecondary = Color(red: 0x5D / 255, green: 0x58 / 255, blue: 0x78 / 255) // #5d5878
    static let blush = Color(red: 0xEE / 255, green: 0x8A / 255, blue: 0x9C / 255)        // #ee8a9c (mouth, cheeks, every accent)
    static let rice = Color.white
    static let riceShade = Color(red: 0xEC / 255, green: 0xE6 / 255, blue: 0xF2 / 255)    // soft edge shading
    static let grainLine = Color(red: 0xE9 / 255, green: 0xE3 / 255, blue: 0xD7 / 255)    // faint grain texture
    /// Mostly-solid frosted tint, so the HUD looks the same over any wallpaper.
    static let panelTint = Color(red: 252 / 255, green: 250 / 255, blue: 1).opacity(0.86)
    static let panelEdge = Color.white.opacity(0.6)
    static let shadow = Color(red: 30 / 255, green: 20 / 255, blue: 70 / 255).opacity(0.16)

    // Shape
    static let cardRadius: CGFloat = 20
    /// Transparent room around the HUD so its soft shadow isn't clipped by the window.
    static let shadowRoom: CGFloat = 14

    /// SF Rounded: the native match for the canvas's Nunito, with no font bundling.
    static func font(_ size: Double, _ weight: Font.Weight = .regular, scale: Double = 1) -> Font {
        .system(size: size * scale, weight: weight, design: .rounded)
    }
}

/// Frosted panel: thin material under a light tint, a white hairline (blush when Flow
/// needs an answer) and a soft lavender-gray shadow.
struct FlowGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(FlowTheme.panelTint)
                }
            }
            .overlay {
                shape.strokeBorder(emphasized ? FlowTheme.blush : FlowTheme.panelEdge, lineWidth: emphasized ? 2 : 1)
            }
            .shadow(color: FlowTheme.shadow, radius: 12, x: 0, y: 6)
    }
}

extension View {
    func flowGlass<S: InsettableShape>(_ shape: S, emphasized: Bool = false) -> some View {
        modifier(FlowGlass(shape: shape, emphasized: emphasized))
    }
}
