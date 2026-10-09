import SwiftUI

/// Small block-level Markdown: paragraphs, headings, lists, quotes and code
/// fences. Inline styles come from Foundation's Markdown parser.
struct MarkdownText: View {
    let source: String

    private enum Block: Hashable {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String, ordinal: String?)
        case quote(String)
        case code(String, lang: String)
        case list([Block])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    private func view(for block: Block) -> AnyView {
        AnyView(blockView(block))
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            Text(Self.inline(s)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let s):
            Text(Self.inline(s))
                .font(level <= 1 ? .title2.weight(.semibold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 4)
        case .bullet(let s, let ordinal):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordinal ?? "•").foregroundStyle(.secondary).monospacedDigit()
                Text(Self.inline(s)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .quote(let s):
            Text(Self.inline(s))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 3) }
        case .code(let code, let lang):
            CodeBlock(code: code, lang: lang)
        case .list(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in view(for: item) }
            }
        }
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        var lang = ""
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code {
                    blocks.append(.code(c.joined(separator: "\n"), lang: lang))
                    code = nil
                } else {
                    flush()
                    code = []
                    lang = String(line.dropFirst(3))
                }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush(); blocks.append(.heading(m.1.count, String(m.2)))
            } else if let m = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flush(); blocks.append(.bullet(String(m.1), ordinal: nil))
            } else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flush(); blocks.append(.bullet(String(m.2), ordinal: "\(m.1)."))
            } else if let m = line.firstMatch(of: /^>\s?(.*)$/) {
                flush(); blocks.append(.quote(String(m.1)))
            } else {
                para.append(raw)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"), lang: lang)) }
        flush()
        // Consecutive bullets read as one list.
        var grouped: [Block] = []
        for b in blocks {
            if case .bullet = b {
                if case .list(let items)? = grouped.last {
                    grouped[grouped.count - 1] = .list(items + [b])
                } else {
                    grouped.append(.list([b]))
                }
            } else {
                grouped.append(b)
            }
        }
        return grouped
    }
}

private struct CodeBlock: View {
    let code: String
    let lang: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "código" : lang).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider().opacity(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
        }
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}
