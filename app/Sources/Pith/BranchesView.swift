import SwiftUI

/// The memory drawn as a small grove, in line art and the app's wood palette.
/// Every message starts as a leaf; pairs of leaves join into twigs, twigs into
/// branches, branches into a trunk. The leaves you see are the lines Pith
/// actually reads: pale sapwood ones are recent messages kept whole, dark
/// heartwood ones are old talk condensed. The big tree on the left is the
/// past; the saplings on the right are today.
struct BranchesView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var scale: CGFloat = 1
    @State private var hovered: BranchNode?
    @State private var zoom: ZoomTarget?

    var body: some View {
        Group {
            if let b = store.branches, b.total > 0 {
                let grove = Grove(b, scale: scale)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, size in grove.draw(ctx, size: size, hovered: hovered?.key, dark: scheme == .dark) }
                        ForEach(grove.leaves) { leaf in
                            Circle()
                                .fill(Color.clear)
                                .frame(width: leaf.radius * 2 + 8, height: leaf.radius * 2 + 8)
                                .contentShape(Circle())
                                .position(leaf.center)
                                .onHover { inside in
                                    if inside { hovered = leaf.node } else if hovered == leaf.node { hovered = nil }
                                }
                                .onTapGesture { zoom = ZoomTarget(id: leaf.node.id, n: leaf.node.n) }
                                .accessibilityLabel(leaf.node.n == 1 ? "Mensagem \(leaf.node.id)" : "\(leaf.node.n) mensagens a partir da \(leaf.node.id)")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(width: grove.size.width, height: grove.size.height)
                }
                .defaultScrollAnchor(.bottomTrailing)
                .background(sky)
                .overlay(alignment: .topLeading) { header(b, grove) }
                .overlay(alignment: .bottom) { detail }
            } else {
                VStack(spacing: 10) {
                    LeafIcon(color: Leaf.color(3, dark: scheme == .dark)).frame(width: 34, height: 34)
                    Text("Sua árvore ainda é uma semente.").font(.headline)
                    Text("Cada mensagem vira uma folha. Comece a conversar e veja ela crescer.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(sky)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $scale, in: 0.6...1.8).frame(width: 120)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .help("Aproximar")
            }
        }
        .navigationTitle("Árvore")
        .onAppear { store.loadBranches() }
        .onChange(of: store.stats.nodes) { store.loadBranches() }
        .onChange(of: store.stats.messages) { store.loadBranches() }
        .sheet(item: $zoom) { target in
            ZoomSheet(root: target).environment(store)
        }
    }

    private var sky: some View {
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
    }

    private func header(_ b: Branches, _ grove: Grove) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sua árvore").font(.system(.title2, design: .serif))
            Text("\(b.total.formatted()) mensagens viraram \(b.cut.count) \(b.cut.count == 1 ? "folha" : "folhas")")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                legend(level: 0, "Folhas claras: mensagens recentes, inteiras")
                legend(level: 7, "Folhas escuras: conversas antigas, resumidas")
            }
            Text("Passe o mouse numa folha para ler; clique para abrir.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(16)
    }

    private func legend(level: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            LeafIcon(color: Leaf.color(level, dark: scheme == .dark)).frame(width: 14, height: 14)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let node = hovered {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LeafIcon(color: Leaf.color(node.l, dark: scheme == .dark)).frame(width: 14, height: 14)
                    Text(node.n == 1 ? "Mensagem \(node.id)" : "\(node.n) mensagens resumidas")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("Clique para abrir").font(.caption).foregroundStyle(.tertiary)
                }
                Text(node.text ?? "Ainda resumindo…")
                    .font(.callout)
                    .foregroundStyle(node.text == nil ? .tertiary : .primary)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: 620, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .padding(16)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Leaves

enum Leaf {
    /// The app's wood palette: sapwood for fresh messages, heartwood for the
    /// condensed past. On light backgrounds the scale shifts darker so pale
    /// sapwood still reads.
    static func color(_ level: Int, dark: Bool) -> Color {
        Theme.stratum(dark ? level : min(level + 3, 10))
    }

    /// A leaf with its stalk at the origin, pointing along +x: a short
    /// petiole, then an asymmetric blade with a drawn-out tip.
    static func path(length L: CGFloat) -> Path {
        var p = Path()
        let base = CGPoint(x: L * 0.16, y: 0)
        p.move(to: base)
        p.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: L * 0.30, y: -L * 0.36), control2: CGPoint(x: L * 0.78, y: -L * 0.24))
        p.addCurve(to: base, control1: CGPoint(x: L * 0.74, y: L * 0.26), control2: CGPoint(x: L * 0.34, y: L * 0.34))
        p.closeSubpath()
        return p
    }

    /// Petiole, midrib and three pairs of side veins.
    static func veins(length L: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: L * 0.9, y: -L * 0.02), control: CGPoint(x: L * 0.5, y: L * 0.03))
        for t in [0.36, 0.54, 0.70] as [CGFloat] {
            let at = CGPoint(x: L * t, y: L * 0.012)
            let reach = L * 0.2 * (1.1 - t)
            p.move(to: at)
            p.addQuadCurve(to: CGPoint(x: at.x + reach * 1.1, y: -reach * 1.25), control: CGPoint(x: at.x + reach * 0.3, y: -reach * 0.7))
            p.move(to: at)
            p.addQuadCurve(to: CGPoint(x: at.x + reach * 1.1, y: reach * 1.3), control: CGPoint(x: at.x + reach * 0.3, y: reach * 0.75))
        }
        return p
    }
}

struct LeafIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let length = size.width * 1.35
            let t = CGAffineTransform(translationX: 1, y: size.height - 1).rotated(by: -.pi / 4)
            ctx.stroke(Leaf.path(length: length).applying(t), with: .color(color), lineWidth: 1.1)
            ctx.stroke(Leaf.veins(length: length).applying(t), with: .color(color.opacity(0.8)), lineWidth: 0.6)
        }
    }
}

// MARK: - Layout

/// A deterministic random stream, so the grove looks the same every time.
private struct Seeded {
    var state: UInt64
    init(_ l: Int, _ i: Int) { state = UInt64(truncatingIfNeeded: l &* 1_000_003 &+ i &* 7919 &+ 17) | 1 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

struct Grove {
    struct Limb { let from: CGPoint; let to: CGPoint; let control: CGPoint; let startWidth: CGFloat; let endWidth: CGFloat }
    struct LeafSpot: Identifiable {
        let node: BranchNode
        let center: CGPoint
        let radius: CGFloat
        let leaves: [(at: CGPoint, angle: CGFloat, length: CGFloat)]
        var id: String { node.key }
    }

    var limbs: [Limb] = []
    var leaves: [LeafSpot] = []
    var trunks: [CGPoint] = []
    var ground: CGFloat = 0
    var size: CGSize = .zero

    init(_ b: Branches, scale: CGFloat) {
        var byKey: [String: BranchNode] = [:]
        for n in b.cut + b.ancestors { byKey[n.key] = n }
        let cutKeys = Set(b.cut.map(\.key))
        // Trunks are the nodes with no parent, oldest first.
        let roots = (b.cut + b.ancestors)
            .filter { byKey["\($0.l + 1):\($0.i >> 1)"] == nil }
            .sorted { $0.id < $1.id }

        let unit = 34 * scale
        let tallest = CGFloat(roots.map(\.l).max() ?? 0)
        let height = unit * (2.6 + tallest * 0.95) + 220
        ground = height - 60
        var x: CGFloat = 80

        for root in roots {
            // Room for the crown, which grows with the size of the tree.
            let crown = unit * (1.4 + CGFloat(root.l) * 1.15)
            x += crown
            let base = CGPoint(x: x, y: ground)
            trunks.append(base)
            let trunk = unit * (1.3 + CGFloat(root.l) * 0.35)
            grow(root, from: base, angle: -.pi / 2, length: trunk, top: root.l, byKey: byKey, cut: cutKeys, depth: 0)
            x += crown
        }
        size = CGSize(width: max(x + 80, 640), height: height)
    }

    private mutating func grow(_ node: BranchNode, from: CGPoint, angle: CGFloat, length: CGFloat,
                               top: Int, byKey: [String: BranchNode], cut: Set<String>, depth: Int,
                               startWidth: CGFloat? = nil) {
        var rng = Seeded(node.l, node.i)
        let bend = (rng.next() - 0.5) * 0.25
        let to = CGPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
        let mid = CGPoint(x: (from.x + to.x) / 2 + cos(angle + .pi / 2) * length * bend,
                          y: (from.y + to.y) / 2 + sin(angle + .pi / 2) * length * bend)
        // Thickness follows how much of the conversation flows through here.
        // Wood tapers from the trunk to the twigs.
        let width = 1.6 + CGFloat(node.l) * 1.9
        limbs.append(Limb(from: from, to: to, control: mid, startWidth: startWidth ?? width * 1.25, endWidth: width * 0.82))

        if cut.contains(node.key) {
            addLeaves(node, at: to, angle: angle, rng: &rng)
            return
        }
        let kids = ["\(node.l - 1):\(2 * node.i)", "\(node.l - 1):\(2 * node.i + 1)"].compactMap { byKey[$0] }
        if kids.isEmpty {
            addLeaves(node, at: to, angle: angle, rng: &rng)
            return
        }
        // Branches fan out, then curve back up towards the light.
        let spread = 0.32 + 0.22 * rng.next() + CGFloat(depth) * 0.015
        for (k, child) in kids.enumerated() {
            let side: CGFloat = kids.count == 1 ? 0 : (k == 0 ? -1 : 1)
            var a = angle + side * spread + (rng.next() - 0.5) * 0.12
            a = a * 0.86 + (-.pi / 2) * 0.14
            let next = length * (0.74 + 0.08 * rng.next())
            grow(child, from: to, angle: a, length: next, top: top, byKey: byKey, cut: cut, depth: depth + 1,
                 startWidth: width * 0.82)
        }
    }

    private mutating func addLeaves(_ node: BranchNode, at tip: CGPoint, angle: CGFloat, rng: inout Seeded) {
        // Condensed leaves are bigger clusters: they hold more of the past.
        let count = 3 + min(node.l / 2, 3)
        let radius = 20 + CGFloat(node.l) * 3
        var spots: [(CGPoint, CGFloat, CGFloat)] = []
        for k in 0..<count {
            let a = angle + (CGFloat(k) / CGFloat(max(count - 1, 1)) - 0.5) * 2.2 + (rng.next() - 0.5) * 0.5
            let at = CGPoint(x: tip.x + cos(a) * 2, y: tip.y + sin(a) * 2)
            spots.append((at, a, 22 + CGFloat(node.l) * 2.6 + rng.next() * 8))
        }
        leaves.append(LeafSpot(node: node, center: tip, radius: radius, leaves: spots))
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, hovered: String?, dark: Bool) {
        // One hairline of ground.
        var groundLine = Path()
        groundLine.move(to: CGPoint(x: 32, y: ground))
        groundLine.addLine(to: CGPoint(x: size.width - 32, y: ground))
        ctx.stroke(groundLine, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

        // Wood in contour: both edges of each limb, filled with the paper
        // so crossings read like an ink drawing; twigs are a single line.
        let wood = Theme.stratum(dark ? 4 : 7)
        let paper = Color(nsColor: .windowBackgroundColor)
        for limb in limbs {
            if limb.startWidth < 4.5 {
                var p = Path()
                p.move(to: limb.from)
                p.addQuadCurve(to: limb.to, control: limb.control)
                ctx.stroke(p, with: .color(wood), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                continue
            }
            let (outline, edges) = Self.contour(limb)
            ctx.fill(outline, with: .color(paper))
            ctx.stroke(edges, with: .color(wood), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
        // The pith: an amber dot where each tree meets the ground.
        for base in trunks {
            let r: CGFloat = 3
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - r, y: base.y - r, width: r * 2, height: r * 2)), with: .color(Theme.heartwood))
        }

        // Leaves drawn like a botanical plate: paper fill, outline, veins.
        // The hovered cluster is washed in amber.
        for spot in leaves {
            let lit = spot.node.key == hovered
            let color = lit ? Theme.heartwood : Leaf.color(spot.node.l, dark: dark)
            for leaf in spot.leaves {
                let length = leaf.length * (lit ? 1.08 : 1)
                let t = CGAffineTransform(translationX: leaf.at.x, y: leaf.at.y).rotated(by: leaf.angle)
                let shape = Leaf.path(length: length).applying(t)
                ctx.fill(shape, with: .color(paper))
                if lit { ctx.fill(shape, with: .color(Theme.heartwood.opacity(0.22))) }
                let ink = spot.node.built ? color : color.opacity(0.45)
                ctx.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                ctx.stroke(Leaf.veins(length: length).applying(t), with: .color(ink.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
    }
}

extension Grove {
    /// A tapering limb offset to both sides: the closed shape (for the paper
    /// fill) and just its two edges (for the ink), so joints don't show seams.
    static func contour(_ limb: Limb) -> (shape: Path, edges: Path) {
        func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(sqrt(dx * dx + dy * dy), 0.001)
            return CGPoint(x: -dy / len, y: dx / len)
        }
        let n0 = normal(limb.from, limb.control), n1 = normal(limb.control, limb.to)
        let nm = normal(limb.from, limb.to)
        let w0 = limb.startWidth / 2, w1 = limb.endWidth / 2, wm = (w0 + w1) / 2
        func off(_ p: CGPoint, _ n: CGPoint, _ w: CGFloat) -> CGPoint { CGPoint(x: p.x + n.x * w, y: p.y + n.y * w) }
        var shape = Path()
        shape.move(to: off(limb.from, n0, w0))
        shape.addQuadCurve(to: off(limb.to, n1, w1), control: off(limb.control, nm, wm))
        shape.addLine(to: off(limb.to, n1, -w1))
        shape.addQuadCurve(to: off(limb.from, n0, -w0), control: off(limb.control, nm, -wm))
        shape.closeSubpath()
        var edges = Path()
        edges.move(to: off(limb.from, n0, w0))
        edges.addQuadCurve(to: off(limb.to, n1, w1), control: off(limb.control, nm, wm))
        edges.move(to: off(limb.from, n0, -w0))
        edges.addQuadCurve(to: off(limb.to, n1, -w1), control: off(limb.control, nm, -wm))
        return (shape, edges)
    }
}
