import SwiftUI

/// The memory drawn as a small grove. Every message starts as a leaf; pairs
/// of leaves join into twigs, twigs into branches, branches into a trunk.
/// The leaves you see are the lines Pith actually reads: fresh green ones are
/// recent messages kept whole, golden ones are old talk condensed. The big
/// tree on the left is the past; the saplings on the right are today.
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
                    Image(systemName: "tree").font(.system(size: 40)).foregroundStyle(Leaf.color(0))
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
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.07, green: 0.09, blue: 0.13), Color(red: 0.11, green: 0.13, blue: 0.14)]
                : [Color(red: 0.87, green: 0.93, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 0.92)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func header(_ b: Branches, _ grove: Grove) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sua árvore").font(.system(.title2, design: .serif))
            Text("\(b.total.formatted()) mensagens viraram \(b.cut.count) \(b.cut.count == 1 ? "folha" : "folhas")")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                legend(level: 0, "Folhas verdes: mensagens recentes, inteiras")
                legend(level: 5, "Folhas douradas: conversas antigas, resumidas")
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
            LeafIcon(color: Leaf.color(level)).frame(width: 12, height: 12)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let node = hovered {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LeafIcon(color: Leaf.color(node.l)).frame(width: 12, height: 12)
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
    /// Spring green for fresh messages, through gold, to autumn russet for the condensed past.
    static func color(_ level: Int) -> Color {
        let stops: [(Double, Double, Double)] = [
            (0.47, 0.76, 0.38), (0.62, 0.78, 0.33), (0.80, 0.77, 0.30),
            (0.89, 0.70, 0.25), (0.88, 0.56, 0.20), (0.78, 0.40, 0.18), (0.62, 0.30, 0.16),
        ]
        let t = min(Double(level) / 8, 1) * Double(stops.count - 1)
        let a = stops[Int(t)], b = stops[min(Int(t) + 1, stops.count - 1)], f = t - t.rounded(.down)
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }

    /// A leaf with its base at the origin, pointing along +x.
    static func path(length: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.45, y: -length * 0.42))
        p.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: length * 0.42))
        return p
    }
}

struct LeafIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let t = CGAffineTransform(translationX: 1, y: size.height - 1).rotated(by: -.pi / 4)
            ctx.fill(Leaf.path(length: size.width * 1.3).applying(t), with: .color(color))
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
    struct Limb { let from: CGPoint; let to: CGPoint; let control: CGPoint; let width: CGFloat }
    struct LeafSpot: Identifiable {
        let node: BranchNode
        let center: CGPoint
        let radius: CGFloat
        let leaves: [(at: CGPoint, angle: CGFloat, length: CGFloat)]
        var id: String { node.key }
    }

    var limbs: [Limb] = []
    var leaves: [LeafSpot] = []
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

        let unit = 30 * scale
        let tallest = CGFloat(roots.map(\.l).max() ?? 0)
        let height = unit * (2.6 + tallest * 0.95) + 220
        ground = height - 60
        var x: CGFloat = 80

        for root in roots {
            // Room for the crown, which grows with the size of the tree.
            let crown = unit * (1.4 + CGFloat(root.l) * 1.15)
            x += crown
            let base = CGPoint(x: x, y: ground)
            let trunk = unit * (1.3 + CGFloat(root.l) * 0.35)
            grow(root, from: base, angle: -.pi / 2, length: trunk, top: root.l, byKey: byKey, cut: cutKeys, depth: 0)
            x += crown
        }
        size = CGSize(width: max(x + 80, 640), height: height)
    }

    private mutating func grow(_ node: BranchNode, from: CGPoint, angle: CGFloat, length: CGFloat,
                               top: Int, byKey: [String: BranchNode], cut: Set<String>, depth: Int) {
        var rng = Seeded(node.l, node.i)
        let bend = (rng.next() - 0.5) * 0.25
        let to = CGPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
        let mid = CGPoint(x: (from.x + to.x) / 2 + cos(angle + .pi / 2) * length * bend,
                          y: (from.y + to.y) / 2 + sin(angle + .pi / 2) * length * bend)
        // Thickness follows how much of the conversation flows through here.
        let width = max(1.2, 2.2 * sqrt(CGFloat(node.n))) * 0.55 + CGFloat(node.l) * 0.5
        limbs.append(Limb(from: from, to: to, control: mid, width: width))

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
            grow(child, from: to, angle: a, length: next, top: top, byKey: byKey, cut: cut, depth: depth + 1)
        }
    }

    private mutating func addLeaves(_ node: BranchNode, at tip: CGPoint, angle: CGFloat, rng: inout Seeded) {
        // Condensed leaves are bigger clusters: they hold more of the past.
        let count = 5 + min(node.l, 6)
        let radius = 11 + CGFloat(node.l) * 2.4
        var spots: [(CGPoint, CGFloat, CGFloat)] = []
        for k in 0..<count {
            let a = angle + (CGFloat(k) / CGFloat(count) - 0.5) * 2.6 + (rng.next() - 0.5) * 0.4
            let r = radius * (0.25 + 0.5 * rng.next())
            let at = CGPoint(x: tip.x + cos(a) * r * 0.5, y: tip.y + sin(a) * r * 0.5)
            spots.append((at, a, 9 + CGFloat(node.l) * 1.3 + rng.next() * 5))
        }
        leaves.append(LeafSpot(node: node, center: tip, radius: radius, leaves: spots))
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, hovered: String?, dark: Bool) {
        // A soft hill for the grove to stand on.
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: ground + 6))
        hill.addCurve(to: CGPoint(x: size.width, y: ground + 6),
                      control1: CGPoint(x: size.width * 0.3, y: ground - 18),
                      control2: CGPoint(x: size.width * 0.7, y: ground - 10))
        hill.addLine(to: CGPoint(x: size.width, y: size.height))
        hill.addLine(to: CGPoint(x: 0, y: size.height))
        hill.closeSubpath()
        let grass = dark ? Color(red: 0.16, green: 0.24, blue: 0.16) : Color(red: 0.62, green: 0.78, blue: 0.48)
        ctx.fill(hill, with: .color(grass))

        let bark = dark ? Color(red: 0.55, green: 0.40, blue: 0.28) : Color(red: 0.45, green: 0.31, blue: 0.20)
        for limb in limbs {
            var p = Path()
            p.move(to: limb.from)
            p.addQuadCurve(to: limb.to, control: limb.control)
            ctx.stroke(p, with: .color(bark), style: StrokeStyle(lineWidth: limb.width, lineCap: .round))
        }

        for spot in leaves {
            let color = Leaf.color(spot.node.l)
            let lit = spot.node.key == hovered
            if lit {
                let r = spot.radius + 10
                ctx.fill(Path(ellipseIn: CGRect(x: spot.center.x - r, y: spot.center.y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(0.22)))
            }
            for leaf in spot.leaves {
                let t = CGAffineTransform(translationX: leaf.at.x, y: leaf.at.y).rotated(by: leaf.angle)
                let shape = Leaf.path(length: leaf.length * (lit ? 1.15 : 1)).applying(t)
                ctx.fill(shape, with: .color(spot.node.built ? color : color.opacity(0.45)))
                // A midrib makes them read as leaves, not dots.
                var rib = Path()
                rib.move(to: .zero)
                rib.addLine(to: CGPoint(x: leaf.length * 0.8, y: 0))
                ctx.stroke(rib.applying(t), with: .color(.black.opacity(0.12)), lineWidth: 0.6)
            }
        }
    }
}
