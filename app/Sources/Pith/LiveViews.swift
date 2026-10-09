import SwiftUI

/// What Pith is doing right now: thinking, tools, helpers, the reply as it streams.
struct LiveTurnView: View {
    let live: LiveTurn
    let runs: [AgentRun]
    let permissions: [PermissionRequest]
    let answer: (PermissionRequest, Bool, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !live.thinking.isEmpty || (live.text.isEmpty && live.tools.isEmpty) {
                ThoughtView(text: live.thinking.isEmpty ? "…" : live.thinking, live: true)
            }
            if !live.tools.isEmpty {
                FlowChips(tools: live.tools.filter { $0.name != "code" })
            }
            ForEach(runs) { run in
                AgentRunCard(run: run, permissions: permissions.filter { $0.agent == run.id }, answer: answer)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
            if !live.text.isEmpty {
                MarkdownText(source: live.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowChips: View {
    let tools: [ToolEvent]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tools) { t in
                HStack(spacing: 5) {
                    if t.state == "running" {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: t.state == "error" ? "exclamationmark.triangle" : "checkmark")
                            .foregroundStyle(t.state == "error" ? .orange : .secondary)
                    }
                    Text(label(t))
                }
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .help(t.result ?? t.summary)
            }
        }
    }

    private func label(_ t: ToolEvent) -> String {
        switch t.name {
        case "zoom": "Abrindo \(t.summary)"
        case "date": "Data de \(t.summary)"
        case "work_log": "Log de \(t.summary)"
        default: t.name
        }
    }
}

/// A Claude Code run in progress, with its permission requests inline.
struct AgentRunCard: View {
    let run: AgentRun
    let permissions: [PermissionRequest]
    let answer: (PermissionRequest, Bool, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(Theme.heartwood)
                    .symbolEffect(.pulse, isActive: !run.done)
                Text(run.id).font(.callout.weight(.semibold))
                Text(run.done ? "terminou" : "trabalhando").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !run.done { ProgressView().controlSize(.small) }
            }
            Text(run.task)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !run.entries.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(run.entries.enumerated()), id: \.offset) { k, e in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: icon(e.kind)).frame(width: 14).foregroundStyle(.tertiary)
                                    Text(e.text).lineLimit(e.kind == "text" ? 4 : 1)
                                }
                                .font(.system(.caption, design: e.kind == "tool" ? .monospaced : .default))
                                .foregroundStyle(.secondary)
                                .id(k)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .onChange(of: run.entries.count) { _, n in
                        withAnimation { proxy.scrollTo(n - 1, anchor: .bottom) }
                    }
                }
            }

            ForEach(permissions) { req in
                PermissionCard(request: req, answer: answer)
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.7), lineWidth: 0.5))
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "tool": "terminal"
        case "result": "checkmark.circle"
        case "error": "xmark.octagon"
        default: "text.alignleft"
        }
    }
}

struct PermissionCard: View {
    let request: PermissionRequest
    let answer: (PermissionRequest, Bool, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("O Claude Code quer usar **\(request.tool)**")
            } icon: {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            Text(request.summary)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            HStack {
                Button("Negar", role: .cancel) { answer(request, false, false) }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Sempre permitir \(request.tool)") { answer(request, true, true) }
                Button("Permitir") { answer(request, true, false) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.heartwood)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .controlSize(.regular)
        }
        .padding(12)
        .background(Color.orange.opacity(0.07), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
    }
}
