import SwiftUI

enum Theme {
    /// The pith: the one accent, used sparingly.
    static let heartwood = Color(red: 0xC9 / 255, green: 0x77 / 255, blue: 0x2E / 255)

    /// Wood from sapwood (fresh, one message) to heartwood (old, many).
    private static let wood: [(Double, Double, Double)] = [
        (0xEA, 0xD9, 0xB5), (0xE2, 0xC2, 0x8A), (0xD9, 0xA8, 0x66),
        (0xC8, 0x8C, 0x4C), (0xB8, 0x74, 0x3A), (0x9A, 0x5A, 0x2B), (0x7A, 0x42, 0x20),
    ]

    /// The color of a memory layer, by how many messages it condenses (2^level).
    static func stratum(_ level: Int) -> Color {
        let t = min(Double(level) / 10.0, 1.0) * Double(wood.count - 1)
        let a = wood[Int(t.rounded(.down))], b = wood[min(Int(t.rounded(.down)) + 1, wood.count - 1)]
        let f = t - t.rounded(.down)
        return Color(
            red: (a.0 + (b.0 - a.0) * f) / 255,
            green: (a.1 + (b.1 - a.1) * f) / 255,
            blue: (a.2 + (b.2 - a.2) * f) / 255
        )
    }

    static let serif = Font.system(.largeTitle, design: .serif).weight(.regular)
    static let mono = Font.system(.caption, design: .monospaced)
}

/// A tree's cross-section: rings packed tight at the center (the condensed
/// past) and wide at the edge (the present), around an amber pith.
struct RingsLogo: View {
    var rings = 9
    var lineWidth: CGFloat = 1.4
    var animated = false
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: !animated || finished)) { timeline in
            let t = min(1, timeline.date.timeIntervalSince(start) / 1.8)
            rings(grown: animated ? 1 - pow(1 - t, 3) : 1)
        }
        .onAppear {
            start = Date()
            Task { try? await Task.sleep(for: .seconds(2)); finished = true }
        }
        .accessibilityHidden(true)
    }

    private func rings(grown: Double) -> some View {
        Canvas { ctx, size in RingsLogo.draw(ctx, size, rings: rings, lineWidth: lineWidth, grown: grown) }
    }

    /// Ring radii widen outward, like the view: dense past, sparse present.
    static func radii(_ count: Int) -> [CGFloat] {
        var out: [CGFloat] = []
        var r: CGFloat = 0.09
        var step: CGFloat = 0.02
        for _ in 0..<count {
            out.append(r)
            r += step
            step *= 1.34
        }
        return out
    }

    static func ring(center c: CGPoint, radius: CGFloat, seed k: Int) -> Path {
        var path = Path()
        let steps = 120
        let phase = Double(k)
        for s in 0...steps {
            let a: Double = Double(s) / Double(steps) * 2 * Double.pi
            let wobble: Double = 0.02 * sin(3 * a + phase) + 0.012 * sin(5 * a + 2 * phase)
            let rr: Double = Double(radius) * (1 + wobble)
            let p = CGPoint(x: c.x + CGFloat(rr * cos(a)), y: c.y + CGFloat(rr * sin(a)))
            if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, rings: Int, lineWidth: CGFloat, grown: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR: CGFloat = (min(size.width, size.height) / 2 - lineWidth) / 1.035
        let all = radii(rings)
        let scale: CGFloat = maxR / (all.last ?? 1)
        let visible = Int((Double(rings) * grown).rounded(.up))
        for (k, r) in all.prefix(visible).enumerated() {
            let t: Double = Double(k) / Double(max(rings - 1, 1))
            let level = Int((1 - t) * 9)
            let color: Color = Theme.stratum(level).opacity(0.55 + 0.45 * t)
            let width: CGFloat = lineWidth * (0.7 + CGFloat(t) * 0.9)
            ctx.stroke(ring(center: c, radius: r * scale, seed: k), with: .color(color), lineWidth: width)
        }
        let dot: CGFloat = maxR * 0.07
        let rect = CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Theme.heartwood))
    }
}
