import SwiftUI

struct ZoomTarget: Identifiable, Hashable {
    let id: Int
    let n: Int
    var key: String { "\(id)+\(n)" }
}

/// The memory as a geological column: one band per line of the view, newest
/// on top. Bands that condense more messages are darker heartwood.
struct StrataInspector: View {
    @Environment(ChatStore.self) private var store
    @State private var zoom: ZoomTarget?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Divider().opacity(0.6)
            if store.view.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Nada guardado ainda").font(.headline)
                    Text("Cada mensagem vira uma camada aqui.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.view.reversed()) { line in
                            band(line)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .sheet(item: $zoom) { target in
            ZoomSheet(root: target)
                .environment(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RingsLogo(rings: 7, lineWidth: 1).frame(width: 26, height: 26)
                Text("Memória").font(.system(.title2, design: .serif))
                Spacer()
            }
            Text("\(store.stats.messages.formatted()) mensagens em \(store.stats.viewLines) camadas")
                .font(.callout)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    stat("Memória ativa", store.stats.viewBytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(store.stats.viewBytes), countStyle: .file) : "—")
                    stat("Lido do cache", store.stats.turnCalls > 0 ? store.stats.cacheHit.formatted(.percent.precision(.fractionLength(0))) : "—")
                }
                GridRow {
                    stat("Condensando", store.stats.pending > 0 ? "\(store.stats.pending)" : "em dia")
                    stat("Gasto", store.stats.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Text(value).font(.callout.monospacedDigit()).contentTransition(.numericText())
        }
    }

    /// Leaves start with their kind ("user: …"); show it as a label instead.
    static func split(_ line: ViewLine) -> (kind: String?, text: String?) {
        guard let text = line.text else { return (nil, nil) }
        if line.n == 1, let m = text.firstMatch(of: /^(user|pith|tool|echo|work|note):\s*/) {
            return (String(m.1), String(text[m.range.upperBound...]))
        }
        return (nil, text)
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "user": "você"
        case "pith": "Pith"
        case "tool": "ferramenta"
        case "echo": "resultado"
        case "work": "Claude Code"
        default: "nota"
        }
    }

    private func band(_ line: ViewLine) -> some View {
        Button {
            zoom = ZoomTarget(id: line.id, n: line.n)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Theme.stratum(line.level))
                    .frame(width: 10)
                VStack(alignment: .leading, spacing: 3) {
                    let parsed = Self.split(line)
                    HStack(spacing: 6) {
                        Text(line.name).font(Theme.mono).foregroundStyle(.secondary)
                        if let kind = parsed.kind {
                            Text(Self.kindLabel(kind)).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                        } else if line.n > 1 {
                            Text("\(line.n) mensagens").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(parsed.text.map(MarkdownText.inline) ?? AttributedString("condensando…"))
                        .font(.callout)
                        .foregroundStyle(line.text == nil ? .tertiary : .primary)
                        .lineLimit(line.level == 0 ? 2 : 3)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 7)
                Spacer(minLength: 0)
            }
            .padding(.trailing, 14)
            .background(hovered == line.name ? Color.primary.opacity(0.05) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .onHover { hovered = $0 ? line.name : (hovered == line.name ? nil : hovered) }
        .help("Abrir \(line.name)")
    }
}

/// Opens a line into its halves, down to whole messages.
struct ZoomSheet: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let root: ZoomTarget
    @State private var path: [ZoomTarget] = []

    private var current: ZoomTarget { path.last ?? root }
    private var result: ZoomResult? {
        guard let z = store.zoom, z.id == current.id, z.n == current.n else { return nil }
        return z
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if !path.isEmpty {
                    Button { path.removeLast() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.key).font(.system(.title3, design: .monospaced))
                    Text(current.n == 1 ? "Mensagem completa" : "\(current.n) mensagens condensadas")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = result {
                        if let m = r.message {
                            HStack {
                                Text(m.kind).font(Theme.mono).foregroundStyle(.secondary)
                                Spacer()
                                if let d = m.timestamp {
                                    Text(d.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            MarkdownText(source: m.text)
                        } else {
                            if let text = r.text {
                                Text(text).font(.body).textSelection(.enabled)
                            }
                            Text("Dividir em")
                                .font(.caption).foregroundStyle(.tertiary)
                                .padding(.top, 6)
                            ForEach(r.children) { child in
                                Button {
                                    path.append(ZoomTarget(id: child.id, n: child.n))
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.stratum(child.level))
                                            .frame(width: 6)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(child.name).font(Theme.mono).foregroundStyle(.secondary)
                                            Text(child.text ?? "condensando…")
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 560, height: 520)
        .onAppear { store.open(id: current.id, n: current.n) }
        .onChange(of: current) { _, t in store.open(id: t.id, n: t.n) }
    }
}
