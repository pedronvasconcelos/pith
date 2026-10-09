import SwiftUI

/// The log, grouped for reading: tool calls and their results fold into one
/// activity row; everything else is one row per message.
enum ChatRow: Identifiable {
    case user(LogMessage)
    case pith(LogMessage)
    case activity([LogMessage])
    case work(LogMessage)
    case note(LogMessage)

    var id: Int {
        switch self {
        case .user(let m), .pith(let m), .work(let m), .note(let m): m.i
        case .activity(let ms): ms.first?.i ?? -1
        }
    }

    static func build(_ messages: [LogMessage]) -> [ChatRow] {
        var rows: [ChatRow] = []
        var group: [LogMessage] = []
        func flush() {
            // A lone Claude Code call is shown by the work card that follows it.
            let onlyCode = group.allSatisfy { $0.kind == "tool" && $0.text.hasPrefix("code(") }
            if !group.isEmpty && !onlyCode { rows.append(.activity(group)) }
            group = []
        }
        for m in messages {
            switch m.kind {
            case "tool", "echo":
                group.append(m)
            case "user": flush(); rows.append(.user(m))
            case "pith": flush(); rows.append(.pith(m))
            case "work": flush(); rows.append(.work(m))
            default: flush(); rows.append(.note(m))
            }
        }
        flush()
        return rows
    }
}

struct UserBubble: View {
    let message: LogMessage

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(MarkdownText.inline(message.text))
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.heartwood.opacity(0.16), in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.heartwood.opacity(0.22), lineWidth: 0.5))
        }
        .help(message.timestamp.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
    }
}

struct PithReply: View {
    let message: LogMessage
    let thought: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thought, !thought.isEmpty { ThoughtView(text: thought, live: false) }
            MarkdownText(source: message.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copiar resposta") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
        }
    }
}

/// A turn's reasoning. Shown, never logged: it lives only in this session.
struct ThoughtView: View {
    let text: String
    let live: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    if live {
                        Text("Pensando").shimmer()
                    } else {
                        Text("Raciocínio")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open || (live && text.count < 400) {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) { Capsule().fill(.quaternary).frame(width: 2) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .textSelection(.enabled)
            }
        }
    }
}

/// Tool calls folded into one quiet line, expandable.
struct ActivityRow: View {
    let messages: [LogMessage]
    @State private var open = false

    private var calls: [LogMessage] { messages.filter { $0.kind == "tool" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: calls.first?.text ?? ""))
                    Text(title)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { m in
                        Text(m.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(m.kind == "tool" ? .primary : .secondary)
                            .lineLimit(m.kind == "tool" ? 3 : 12)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
                .transition(.opacity)
            }
        }
    }

    private var title: String {
        let names = calls.map { $0.text.prefix { $0 != "(" } }
        let zooms = names.filter { $0 == "zoom" || $0 == "work_log" }.count
        let dates = names.filter { $0 == "date" }.count
        let code = names.filter { $0 == "code" }.count
        var parts: [String] = []
        if zooms > 0 { parts.append(zooms == 1 ? "Consultou a memória" : "Consultou a memória \(zooms)×") }
        if dates > 0 { parts.append("conferiu \(dates == 1 ? "uma data" : "\(dates) datas")") }
        if code > 0 { parts.append(code == 1 ? "acionou o Claude Code" : "acionou o Claude Code \(code)×") }
        guard let head = parts.first else { return "Usou ferramentas" }
        parts[0] = head.prefix(1).uppercased() + head.dropFirst()
        return parts.joined(separator: ", ")
    }

    private func icon(for text: String) -> String {
        if text.hasPrefix("code") { return "hammer" }
        if text.hasPrefix("date") { return "calendar" }
        return "square.stack.3d.down.right"
    }
}

/// The report a Claude Code run sent back.
struct WorkCard: View {
    let message: LogMessage
    @State private var open = false

    private var name: String {
        message.text.firstMatch(of: /^\[([^\]]+)\]/).map { String($0.1) } ?? "Claude Code"
    }
    private var report: String {
        message.text.replacing(/^\[[^\]]+\]\s*/, with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill").foregroundStyle(Theme.heartwood)
                Text(name).font(.callout.weight(.semibold))
                Text("relatório").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(open ? "Recolher" : "Expandir") {
                    withAnimation(.smooth(duration: 0.25)) { open.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
            MarkdownText(source: report)
                .lineLimit(open ? nil : 6)
                .font(.callout)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.7), lineWidth: 0.5))
    }
}

struct NoteRow: View {
    let message: LogMessage
    var body: some View {
        Label(message.text, systemImage: "pin")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Shimmer

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
