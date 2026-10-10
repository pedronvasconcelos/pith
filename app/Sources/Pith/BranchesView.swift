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
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
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
                .defaultScrollAnchor(.trailing)
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
            Text("Role para o lado para voltar no tempo. Passe o mouse numa folha para ler; clique para abrir.")
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

    /// Petiole and midrib only: the clean version.
    static func midrib(length L: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: L * 0.88, y: -L * 0.02), control: CGPoint(x: L * 0.5, y: L * 0.035))
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

/// One tree, read left to right like time. A single fine stem runs from the
/// first message to now. At every fork the older half leaves the stem as a
/// side branch, alternating up and down, and the newer half carries the stem
/// on, so the present is always at the growing tip. Leaves are the lines Pith
/// reads; bigger, darker leaves hold more of the condensed past.
struct Grove {
    struct Limb { let from: CGPoint; let control: CGPoint; let to: CGPoint; let width: CGFloat }
    struct LeafSpot: Identifiable {
        let node: BranchNode
        let base: CGPoint
        let angle: CGFloat
        let length: CGFloat
        var center: CGPoint { CGPoint(x: base.x + cos(angle) * length * 0.55, y: base.y + sin(angle) * length * 0.55) }
        var radius: CGFloat { length * 0.45 }
        var id: String { node.key }
    }

    var limbs: [Limb] = []
    var leaves: [LeafSpot] = []
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var size: CGSize = .zero

    private var byKey: [String: BranchNode] = [:]
    private var cut: Set<String> = []
    private var counts: [String: Int] = [:]
    private let unit: CGFloat

    init(_ b: Branches, scale: CGFloat) {
        unit = 30 * scale
        for n in b.cut + b.ancestors { byKey[n.key] = n }
        cut = Set(b.cut.map(\.key))
        let roots = (b.cut + b.ancestors)
            .filter { byKey["\($0.l + 1):\($0.i >> 1)"] == nil }
            .sorted { $0.id < $1.id }
        guard !roots.isEmpty else { return }

        // The whole chat is one stem running through time. Small branches of
        // a few leaves each sprout from it in order, alternating up and down.
        var at = CGPoint.zero
        var dir: CGFloat = 0
        var side: CGFloat = -1
        for group in roots.flatMap({ groups($0) }) {
            (at, dir) = stem(from: at, dir: dir * 0.6, gap: gap(for: group), seed: group, depth: 0)
            branch(group, from: at, dir: dir, side: side, depth: 0)
            side = -side
        }
        // A last stretch of stem: the growing tip.
        (at, _) = stem(from: at, dir: dir * 0.6, gap: unit * 1.2, seed: roots[roots.count - 1], depth: 0)
        end = at
        layoutBounds()
    }

    private func children(_ n: BranchNode) -> [BranchNode] {
        ["\(n.l - 1):\(2 * n.i)", "\(n.l - 1):\(2 * n.i + 1)"].compactMap { byKey[$0] }
    }

    private mutating func count(_ n: BranchNode) -> Int {
        if let c = counts[n.key] { return c }
        let c = cut.contains(n.key) ? 1 : max(children(n).reduce(0) { $0 + count($1) }, 1)
        counts[n.key] = c
        return c
    }

    /// Splits the tree into branches of at most a handful of leaves, oldest first.
    private mutating func groups(_ n: BranchNode) -> [BranchNode] {
        if count(n) <= 6 || cut.contains(n.key) { return [n] }
        return children(n).flatMap { groups($0) }
    }

    /// Room along the stem for a side branch, so neighbours don't tangle.
    /// Branches alternate sides, so each only needs about half its width.
    private mutating func gap(for n: BranchNode) -> CGFloat {
        unit * (0.75 + 0.5 * CGFloat(count(n)))
    }

    /// Extends a stem by `gap`, with a gentle sway; returns where it ends.
    private mutating func stem(from: CGPoint, dir: CGFloat, gap: CGFloat, seed: BranchNode, depth: Int) -> (CGPoint, CGFloat) {
        var rng = Seeded(seed.l, seed.i)
        let sway = (rng.next() - 0.5) * 0.16
        let newDir = dir + sway
        let to = CGPoint(x: from.x + cos(newDir) * gap, y: from.y + sin(newDir) * gap)
        let control = CGPoint(x: from.x + cos(dir) * gap * 0.55, y: from.y + sin(dir) * gap * 0.55)
        limbs.append(Limb(from: from, control: control, to: to, width: depth == 0 ? 1.5 : 1.1))
        return (to, newDir)
    }

    private mutating func branch(_ n: BranchNode, from: CGPoint, dir: CGFloat, side: CGFloat, depth: Int) {
        var rng = Seeded(n.l &+ 7, n.i)
        let angle = (depth == 0 ? 0.95 : 0.72) + (rng.next() - 0.5) * 0.2
        grow(n, from: from, dir: dir + side * angle, depth: depth + 1, side: -side)
    }

    /// A node either ends in a leaf or forks: the older child branches off,
    /// the newer one carries this stem on.
    private mutating func grow(_ n: BranchNode, from: CGPoint, dir: CGFloat, depth: Int, side: CGFloat) {
        if cut.contains(n.key) {
            var rng = Seeded(n.l, n.i &+ 3)
            let twig = unit * 0.45
            let d = dir + (rng.next() - 0.5) * 0.5
            let tip = CGPoint(x: from.x + cos(d) * twig, y: from.y + sin(d) * twig)
            limbs.append(Limb(from: from, control: CGPoint(x: (from.x + tip.x) / 2, y: (from.y + tip.y) / 2), to: tip, width: 1))
            let length = unit * (1.05 + CGFloat(min(n.l, 7)) * 0.16) + rng.next() * unit * 0.25
            leaves.append(LeafSpot(node: n, base: tip, angle: d + (rng.next() - 0.5) * 0.4, length: length))
            return
        }
        let kids = children(n)
        guard let newer = kids.last else { return }
        if kids.count == 2 {
            let older = kids[0]
            let (at, d) = stem(from: from, dir: dir, gap: gap(for: older), seed: n, depth: depth)
            branch(older, from: at, dir: d, side: side, depth: depth)
            // Side branches drift back towards the stem's direction, like the reference vine.
            grow(newer, from: at, dir: depth == 0 ? d : d * 0.92, depth: depth, side: -side)
        } else {
            grow(newer, from: from, dir: dir, depth: depth, side: side)
        }
    }

    /// Moves everything into positive space with margins.
    private mutating func layoutBounds() {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func add(_ p: CGPoint, _ r: CGFloat = 0) {
            minX = min(minX, p.x - r); maxX = max(maxX, p.x + r)
            minY = min(minY, p.y - r); maxY = max(maxY, p.y + r)
        }
        for l in limbs { add(l.from); add(l.to) }
        for leaf in leaves { add(leaf.center, leaf.length * 0.6) }
        let margin: CGFloat = 90
        let dx = margin - minX, dy = margin + 70 - minY
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        limbs = limbs.map { Limb(from: move($0.from), control: move($0.control), to: move($0.to), width: $0.width) }
        leaves = leaves.map { LeafSpot(node: $0.node, base: move($0.base), angle: $0.angle, length: $0.length) }
        start = move(.zero)
        end = move(end)
        size = CGSize(width: max(maxX - minX + margin * 2, 640), height: max(maxY - minY + margin * 2 + 70, 420))
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, hovered: String?, dark: Bool) {
        let wood = Theme.stratum(dark ? 3 : 7)
        let paper = Color(nsColor: .windowBackgroundColor)
        for limb in limbs {
            var p = Path()
            p.move(to: limb.from)
            p.addQuadCurve(to: limb.to, control: limb.control)
            ctx.stroke(p, with: .color(wood), style: StrokeStyle(lineWidth: limb.width, lineCap: .round))
        }
        // The pith: where the first message grew from.
        let r: CGFloat = 3.5
        ctx.fill(Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)), with: .color(Theme.heartwood))

        for leaf in leaves {
            let lit = leaf.node.key == hovered
            let color = lit ? Theme.heartwood : Leaf.color(leaf.node.l, dark: dark)
            let length = leaf.length * (lit ? 1.06 : 1)
            let t = CGAffineTransform(translationX: leaf.base.x, y: leaf.base.y).rotated(by: leaf.angle)
            let shape = Leaf.path(length: length).applying(t)
            ctx.fill(shape, with: .color(paper))
            if lit { ctx.fill(shape, with: .color(Theme.heartwood.opacity(0.2))) }
            let ink = leaf.node.built ? color : color.opacity(0.45)
            ctx.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: 1.15, lineJoin: .round))
            ctx.stroke(Leaf.midrib(length: length).applying(t), with: .color(ink.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }

        // Where the reading starts and where it is now.
        ctx.draw(Text("primeira mensagem").font(.caption).foregroundStyle(.tertiary),
                 at: CGPoint(x: start.x, y: start.y + 22), anchor: .top)
        ctx.draw(Text("agora").font(.caption).foregroundStyle(.tertiary),
                 at: CGPoint(x: end.x + 12, y: end.y), anchor: .leading)
    }
}
