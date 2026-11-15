import AppKit
import FlowHUD
import SwiftUI

// MARK: - Mood

/// The mascot's face. Derived from the HUD state; the HUD still shows the activity in words.
enum MascotMood: Equatable {
    case idle, hello, listening, speaking, working, done, needsYou

    /// - Parameter flash: a just-finished outcome, shown for a few seconds (see `HUDView`).
    init(activity: HUDActivity, flash: HUDOutcomeKind?) {
        switch activity {
        case .error: self = .needsYou
        case .speaking: self = .speaking
        case .processing: self = .working
        case .awaitingChoice, .awaitingAnswer, .awaitingConfirmation: self = .listening
        case .listening, .hearing, .idle:
            switch flash {
            case .verified?: self = .done
            case .notDone?: self = .needsYou
            default: self = activity == .idle ? .idle : .listening
            }
        }
    }

    /// Faces whose accents pulse or orbit. idle, hello and needsYou are still pictures.
    var hasMotion: Bool {
        switch self {
        case .listening, .speaking, .working, .done: true
        case .idle, .hello, .needsYou: false
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: "Flow is resting"
        case .hello: "Flow"
        case .listening: "Flow is listening"
        case .speaking: "Flow is speaking"
        case .working: "Flow is working"
        case .done: "Flow finished"
        case .needsYou: "Flow needs you"
        }
    }
}

// MARK: - View

/// The onigiri mascot: a soft, fluffy rice ball with no hands, floating gently.
/// Drawn in a 112×102 design space (the same coordinates as the canvas).
struct OnigiriMascot: View {
    var mood: MascotMood
    var floating: Bool = true
    /// false draws a still picture (no per-frame redraws), e.g. for the menu bar.
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Something on the face pulses or orbits, so the mascot redraws every frame (and bobs, if floating).
    /// Still faces (asleep, needs you, hello) are drawn once and redrawn only when the mood changes.
    private var moves: Bool { animated && !reduceMotion && mood.hasMotion }
    @Environment(\.displayScale) private var displayScale

    // Performance (measured on this Mac, release build, HUD expanded and idle): redrawing the fluffy
    // body every frame cost ~14% CPU; with the body cached as a bitmap and still faces not animating,
    // an idle HUD costs ~0%. Per frame we only draw the cached bitmap plus a few small accent shapes.
    var body: some View {
        GeometryReader { g in
            let size = g.size
            let figure = FigureCache.image(mood: mood, size: size, scale: displayScale).map { Image(nsImage: $0) }
            if moves {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { c, size in
                        let s = min(size.width / 112, size.height / 102)
                        if floating { OnigiriRenderer.drawFloorShadow(&c, size: size) }
                        // The original bob: -2 - 2·sin(2πt/3) design units, a 3-second cycle.
                        if floating { c.translateBy(x: 0, y: CGFloat(-2 - 2 * sin(t * 2 * .pi / 3)) * s) }
                        Self.drawFigure(&c, size: size, mood: mood, cached: figure)
                        OnigiriRenderer.drawAccents(&c, size: size, mood: mood, time: t)
                    }
                }
            } else {
                Canvas { c, size in
                    if floating && animated && !reduceMotion { OnigiriRenderer.drawFloorShadow(&c, size: size) }
                    Self.drawFigure(&c, size: size, mood: mood, cached: figure)
                    OnigiriRenderer.drawAccents(&c, size: size, mood: mood, time: 0)
                }
            }
        }
        .aspectRatio(112.0 / 102.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(mood.accessibilityLabel)
    }

    private static func drawFigure(_ c: inout GraphicsContext, size: CGSize, mood: MascotMood, cached: Image?) {
        if let cached {
            c.draw(cached, in: CGRect(origin: .zero, size: size))
        } else {
            OnigiriRenderer.drawFigure(&c, size: size, mood: mood)
        }
    }
}

/// The expensive body (blur + alpha threshold + grain texture) rendered once per mood and size.
@MainActor
private enum FigureCache {
    private static var images: [String: NSImage] = [:]

    static func image(mood: MascotMood, size: CGSize, scale: CGFloat) -> NSImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let key = "\(mood)-\(Int(size.width * 10))x\(Int(size.height * 10))@\(scale)"
        if let hit = images[key] { return hit }
        let renderer = ImageRenderer(content: Canvas { c, s in OnigiriRenderer.drawFigure(&c, size: s, mood: mood) }
            .frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        if images.count > 64 { images.removeAll() }  // a handful of moods × sizes; never grows unbounded
        images[key] = image
        return image
    }
}

// MARK: - Geometry

private struct Grain { let x: CGFloat; let y: CGFloat; let angle: CGFloat }

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
}

private enum OnigiriGeometry {
    /// Rounded rice-ball silhouette (design units).
    static let body: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 16))
        p.addCurve(to: CGPoint(x: 64, y: 27), control1: CGPoint(x: 56, y: 16), control2: CGPoint(x: 60, y: 20))
        p.addLine(to: CGPoint(x: 85, y: 64))
        p.addCurve(to: CGPoint(x: 70, y: 88), control1: CGPoint(x: 91, y: 76), control2: CGPoint(x: 84, y: 88))
        p.addLine(to: CGPoint(x: 30, y: 88))
        p.addCurve(to: CGPoint(x: 15, y: 64), control1: CGPoint(x: 16, y: 88), control2: CGPoint(x: 9, y: 76))
        p.addLine(to: CGPoint(x: 36, y: 27))
        p.addCurve(to: CGPoint(x: 50, y: 16), control1: CGPoint(x: 40, y: 20), control2: CGPoint(x: 44, y: 16))
        p.closeSubpath()
        return p
    }()

    private static let tri = [CGPoint(x: 50, y: 30), CGPoint(x: 25, y: 75), CGPoint(x: 75, y: 75)]

    static func inside(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Bool {
        let p = CGPoint(x: x, y: y), a = tri[0], b = tri[1], c = tri[2]
        func sign(_ p: CGPoint, _ q: CGPoint, _ s: CGPoint) -> CGFloat {
            (p.x - s.x) * (q.y - s.y) - (q.x - s.x) * (p.y - s.y)
        }
        let d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        if !(hasNeg && hasPos) { return true }
        return min(segmentDistance(p, a, b), segmentDistance(p, b, c), segmentDistance(p, c, a)) <= r
    }

    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// Evenly spread grains, fixed seed so the mascot looks the same every launch.
    private static let grains: [Grain] = {
        var rng = SplitMix(state: 11)
        var out: [Grain] = []
        for _ in 0..<20_000 {
            let x = 8 + 84 * rng.unit(), y = 12 + 80 * rng.unit()
            guard inside(x, y, 12.5) else { continue }
            if out.allSatisfy({ hypot($0.x - x, $0.y - y) >= 3.3 }) {
                out.append(Grain(x: x, y: y, angle: rng.unit() * .pi))
            }
        }
        return out
    }()

    /// Grains near the border: blended into the body for a soft, fluffy edge.
    static let edge = grains.filter { !inside($0.x, $0.y, 9.5) && inside($0.x, $0.y, 11.5) }
    /// Faint grains on the surface for texture.
    static let texture = grains.enumerated().filter { $0.offset % 2 == 0 && inside($0.element.x, $0.element.y, 9) }.map(\.element)

    static func grain(_ g: Grain, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(rotationAngle: g.angle))
            .applying(CGAffineTransform(translationX: g.x, y: g.y))
    }
}

// MARK: - Renderer

private enum OnigiriRenderer {
    enum Paint { case fill(Color), stroke(Color, CGFloat) }
    struct Mark { var path: Path; var paint: Paint; var opacity: Double = 1 }

    /// Design space → view: scale `s` and the transform that centers the 112×102 drawing.
    private static func layout(_ size: CGSize) -> (s: CGFloat, base: CGAffineTransform) {
        let s = min(size.width / 112, size.height / 102)
        let ox = (size.width - 112 * s) / 2 + 6 * s, oy = (size.height - 102 * s) / 2
        return (s, CGAffineTransform(translationX: ox, y: oy).scaledBy(x: s, y: s))
    }

    private static func bodyTransform(_ base: CGAffineTransform, mood: MascotMood) -> CGAffineTransform {
        mood == .listening
            ? base.translatedBy(x: 50, y: 62).rotated(by: -9 * .pi / 180).translatedBy(x: -50, y: -62)
            : base
    }

    /// The shadow on the "floor" under a floating mascot (it stays put while the mascot bobs).
    static func drawFloorShadow(_ ctx: inout GraphicsContext, size: CGSize) {
        let (_, base) = layout(size)
        ctx.fill(Path(ellipseIn: CGRect(x: 28, y: 95, width: 44, height: 6)).applying(base),
                 with: .color(FlowTheme.ink.opacity(0.12)))
    }

    /// Pulsing/orbiting accents only: a few small shapes, cheap to redraw every frame.
    static func drawAccents(_ ctx: inout GraphicsContext, size: CGSize, mood: MascotMood, time t: Double) {
        let (s, base) = layout(size)
        for m in accents(mood, t: t) { render(m, in: &ctx, transform: base, scale: s) }
    }

    /// The expensive part (body, shading, grain texture, face). Time-independent: drawn once per mood.
    static func drawFigure(_ ctx: inout GraphicsContext, size: CGSize, mood: MascotMood) {
        let (s, lifted) = layout(size)
        let bodyT = bodyTransform(lifted, mood: mood)

        // Fluffy body: grains blended into the silhouette (blur + alpha threshold), soft drop shadow.
        let bodyPath = OnigiriGeometry.body.applying(bodyT)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: FlowTheme.ink.opacity(0.14), radius: 1.8 * s, x: 0, y: 1.4 * s))
            layer.drawLayer { goo in
                goo.addFilter(.alphaThreshold(min: 0.45, color: FlowTheme.rice))
                goo.addFilter(.blur(radius: 2.2 * s))
                goo.fill(bodyPath, with: .color(FlowTheme.rice))
                for g in OnigiriGeometry.edge {
                    goo.fill(OnigiriGeometry.grain(g, rx: 2.6, ry: 3.8).applying(bodyT), with: .color(FlowTheme.rice))
                }
            }
        }
        // Soft edge shading
        let center = CGPoint(x: 46, y: 43).applying(bodyT)
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [.init(color: FlowTheme.riceShade.opacity(0), location: 0.55),
                             .init(color: FlowTheme.riceShade.opacity(0.9), location: 1)]),
            center: center, startRadius: 0, endRadius: 53 * s))
        // Faint grain texture
        ctx.drawLayer { tex in
            tex.opacity = 0.8
            tex.addFilter(.blur(radius: 0.35 * s))
            for g in OnigiriGeometry.texture {
                tex.stroke(OnigiriGeometry.grain(g, rx: 1.6, ry: 2.9).applying(bodyT),
                           with: .color(FlowTheme.grainLine), lineWidth: 0.45 * s)
            }
        }

        // Face and accents
        for m in face(mood) { render(m, in: &ctx, transform: bodyT, scale: s) }
        if mood == .idle {
            drawZ(&ctx, "z", at: CGPoint(x: 79, y: 18).applying(lifted), size: 11 * s, opacity: 1)
            drawZ(&ctx, "z", at: CGPoint(x: 86, y: 9).applying(lifted), size: 8 * s, opacity: 0.7)
        }
    }

    private static func render(_ m: Mark, in ctx: inout GraphicsContext, transform: CGAffineTransform, scale s: CGFloat) {
        var c = ctx
        c.opacity = m.opacity
        let p = m.path.applying(transform)
        switch m.paint {
        case .fill(let color): c.fill(p, with: .color(color))
        case .stroke(let color, let width):
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawZ(_ ctx: inout GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat, opacity: Double) {
        var c = ctx
        c.opacity = opacity
        c.draw(Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(FlowTheme.blush), at: point)
    }

    // MARK: Face parts (design units)

    private static let ink = FlowTheme.ink, blush = FlowTheme.blush

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }
    private static func quad(from a: CGPoint, to b: CGPoint, control c: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addQuadCurve(to: b, control: c); return p
    }
    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    private static func dotEye(_ x: CGFloat, _ y: CGFloat) -> [Mark] {
        [Mark(path: circle(x, y, 3.2), paint: .fill(ink)), Mark(path: circle(x + 1.1, y - 1.2, 1), paint: .fill(.white))]
    }
    private static func bigEye(_ x: CGFloat, _ y: CGFloat) -> [Mark] {
        [Mark(path: circle(x, y, 4.4), paint: .fill(ink)),
         Mark(path: circle(x + 1.4, y - 1.6, 1.5), paint: .fill(.white)),
         Mark(path: circle(x - 1.3, y + 1.6, 0.7), paint: .fill(.white))]
    }
    private static func happyEye(_ x: CGFloat, _ y: CGFloat) -> Mark {
        Mark(path: quad(from: CGPoint(x: x - 4, y: y + 1.5), to: CGPoint(x: x + 4, y: y + 1.5), control: CGPoint(x: x, y: y - 4)),
             paint: .stroke(ink, 2.6))
    }
    private static func closedEye(_ x: CGFloat, _ y: CGFloat) -> Mark {
        Mark(path: quad(from: CGPoint(x: x - 4, y: y - 1), to: CGPoint(x: x + 4, y: y - 1), control: CGPoint(x: x, y: y + 3.5)),
             paint: .stroke(ink, 2.6))
    }
    private static var cheeks: [Mark] {
        [Mark(path: ellipse(30, 55, 5, 3.2), paint: .fill(blush), opacity: 0.45),
         Mark(path: ellipse(70, 55, 5, 3.2), paint: .fill(blush), opacity: 0.45)]
    }
    /// D-shaped open mouth: flat top at `top`, `width` wide, `depth` deep.
    private static func openMouth(top: CGFloat, width: CGFloat, depth: CGFloat) -> Path {
        let l = 50 - width / 2, r = 50 + width / 2
        var p = Path()
        p.move(to: CGPoint(x: l, y: top))
        p.addLine(to: CGPoint(x: r, y: top))
        p.addQuadCurve(to: CGPoint(x: 50, y: top + depth), control: CGPoint(x: r, y: top + depth))
        p.addQuadCurve(to: CGPoint(x: l, y: top), control: CGPoint(x: l, y: top + depth))
        p.closeSubpath()
        return p
    }

    private static func face(_ mood: MascotMood) -> [Mark] {
        switch mood {
        case .idle:
            return [closedEye(40, 48), closedEye(60, 48), Mark(path: ellipse(50, 57, 2.6, 1.8), paint: .fill(blush))] + cheeks
        case .hello:
            return [happyEye(40, 48), happyEye(60, 48), Mark(path: openMouth(top: 55, width: 7, depth: 4.5), paint: .fill(blush))] + cheeks
        case .listening:
            var w = Path()
            w.move(to: CGPoint(x: 47, y: 56))
            w.addQuadCurve(to: CGPoint(x: 50, y: 56), control: CGPoint(x: 48.5, y: 57.8))
            w.addQuadCurve(to: CGPoint(x: 53, y: 56), control: CGPoint(x: 51.5, y: 57.8))
            return bigEye(40, 47) + bigEye(60, 47) + [Mark(path: w, paint: .stroke(ink, 2.2))] + cheeks
        case .speaking:
            return [happyEye(40, 48), happyEye(60, 48), Mark(path: openMouth(top: 54, width: 11, depth: 7.5), paint: .fill(blush))] + cheeks
        case .working:
            return dotEye(42.5, 48) + dotEye(62.5, 48) + [Mark(path: line(CGPoint(x: 47, y: 57), CGPoint(x: 53, y: 57)), paint: .stroke(blush, 2.6))]
        case .done:
            var wink = Path()
            wink.move(to: CGPoint(x: 57, y: 45)); wink.addLine(to: CGPoint(x: 63, y: 48)); wink.addLine(to: CGPoint(x: 57, y: 51))
            var smile = Path()
            smile.move(to: CGPoint(x: 45, y: 54)); smile.addQuadCurve(to: CGPoint(x: 55, y: 54), control: CGPoint(x: 50, y: 60)); smile.closeSubpath()
            return dotEye(40, 48) + [Mark(path: wink, paint: .stroke(ink, 2.6)), Mark(path: smile, paint: .fill(blush))] + cheeks
        case .needsYou:
            return [Mark(path: line(CGPoint(x: 35, y: 41), CGPoint(x: 43, y: 43.5)), paint: .stroke(ink, 2.4)),
                    Mark(path: line(CGPoint(x: 65, y: 41), CGPoint(x: 57, y: 43.5)), paint: .stroke(ink, 2.4))]
                + dotEye(40, 48) + dotEye(60, 48)
                + [Mark(path: quad(from: CGPoint(x: 46, y: 58.5), to: CGPoint(x: 54, y: 58.5), control: CGPoint(x: 50, y: 54)),
                        paint: .stroke(ink, 2.4))]
        }
    }

    // MARK: Accents (all blush)

    /// Gentle 0.35…1 pulse.
    private static func pulse(_ t: Double, period: Double, delay: Double = 0) -> Double {
        0.35 + 0.65 * (0.5 - 0.5 * cos(2 * .pi * (t - delay) / period))
    }

    private static func accents(_ mood: MascotMood, t: Double) -> [Mark] {
        switch mood {
        case .listening:
            // Soft dots drifting in from the left.
            return [Mark(path: circle(2, 40, 2.6), paint: .fill(blush), opacity: pulse(t, period: 1.2)),
                    Mark(path: circle(-2, 52, 2.2), paint: .fill(blush), opacity: 0.75 * pulse(t, period: 1.2, delay: 0.2)),
                    Mark(path: circle(1, 63, 1.8), paint: .fill(blush), opacity: 0.55 * pulse(t, period: 1.2, delay: 0.4))]
        case .speaking:
            // Waves going out to the right.
            return [Mark(path: quad(from: CGPoint(x: 94, y: 46), to: CGPoint(x: 94, y: 66), control: CGPoint(x: 99, y: 56)),
                         paint: .stroke(blush, 3.5), opacity: pulse(t, period: 1.2)),
                    Mark(path: quad(from: CGPoint(x: 100, y: 40), to: CGPoint(x: 100, y: 72), control: CGPoint(x: 107, y: 56)),
                         paint: .stroke(blush, 3), opacity: 0.55 * pulse(t, period: 1.2, delay: 0.2))]
        case .working:
            // Two dots orbiting.
            let a = t * 2 * .pi / 2.4
            func orbit(_ r: Double, _ phase: Double) -> CGPoint {
                CGPoint(x: 50 + r * cos(a + phase), y: 54 + r * sin(a + phase))
            }
            let p1 = orbit(48, -.pi / 2), p2 = orbit(46.5, atan2(-20, 42))
            return [Mark(path: circle(p1.x, p1.y, 3.2), paint: .fill(blush)),
                    Mark(path: circle(p2.x, p2.y, 2.4), paint: .fill(blush))]
        case .done:
            var star = Path()
            let raw: [(CGFloat, CGFloat)] = [(84, 8), (86.6, 13.3), (92.4, 14.1), (88.2, 18.2), (89.2, 24), (84, 21.3),
                                             (78.8, 24), (79.8, 18.2), (75.6, 14.1), (81.4, 13.3)]
            let pts = raw.map { CGPoint(x: $0.0, y: $0.1) }
            star.addLines(pts); star.closeSubpath()
            return [Mark(path: star, paint: .fill(blush), opacity: pulse(t, period: 2))]
        case .needsYou:
            var drop = Path()
            drop.move(to: CGPoint(x: 78, y: 18))
            drop.addQuadCurve(to: CGPoint(x: 78, y: 29), control: CGPoint(x: 72, y: 26))
            drop.addQuadCurve(to: CGPoint(x: 78, y: 18), control: CGPoint(x: 84, y: 26))
            return [Mark(path: drop, paint: .fill(blush))]
        case .hello:
            var heart = Path()
            heart.move(to: CGPoint(x: 16, y: 14))
            heart.addCurve(to: CGPoint(x: 10, y: 18), control1: CGPoint(x: 13, y: 10), control2: CGPoint(x: 7, y: 13))
            heart.addLine(to: CGPoint(x: 16, y: 24))
            heart.addLine(to: CGPoint(x: 22, y: 18))
            heart.addCurve(to: CGPoint(x: 16, y: 14), control1: CGPoint(x: 25, y: 13), control2: CGPoint(x: 19, y: 10))
            heart.closeSubpath()
            return [Mark(path: heart, paint: .fill(blush))]
        case .idle:
            return []
        }
    }
}

// MARK: - Menu bar

/// The tiny mascot for the menu bar. Gets a soft blush pill behind it while listening.
struct MenuBarMascot: View {
    let model: HUDModel

    var body: some View {
        let s = model.state
        // Always a still picture: it is on screen the whole time Flow runs, and the blush
        // pill below already shows listening.
        OnigiriMascot(mood: MascotMood(activity: s.activity, flash: nil), floating: false, animated: false)
            .padding(.horizontal, 3)
            .frame(width: 26, height: 22)
            .background(Capsule().fill(FlowTheme.blush.opacity(s.listening ? 0.28 : 0)))
    }
}

/// An NSHostingView that lets clicks fall through to the status-item button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

#Preview("Moods") {
    HStack(spacing: 24) {
        ForEach([MascotMood.idle, .listening, .speaking, .working, .done, .needsYou], id: \.accessibilityLabel) { mood in
            OnigiriMascot(mood: mood).frame(width: 120, height: 110)
        }
    }
    .padding(40)
    .background(Color(red: 0.97, green: 0.96, blue: 0.98))
}
