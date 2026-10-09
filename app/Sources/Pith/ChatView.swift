import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var position = ScrollPosition(edge: .bottom)

    private let column: CGFloat = 720

    var body: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if store.hasOlder {
                        Button("Mostrar mensagens anteriores") { store.loadOlder() }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(ChatRow.build(store.messages)) { row in
                        rowView(row).id(row.id)
                    }
                    if let live = store.live {
                        LiveTurnView(
                            live: live,
                            runs: store.agents.values.filter { !$0.done }.sorted { $0.id < $1.id },
                            permissions: store.permissions,
                            answer: { store.answer($0, allow: $1, always: $2) }
                        )
                        .id("live")
                        .transition(.opacity)
                    }
                    if let err = store.lastError {
                        ErrorBanner(message: err)
                    }
                }
                .frame(maxWidth: column)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($position)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(draft: $draft, focused: $composerFocused, busy: store.busy,
                         send: send, stop: store.cancel)
                    .frame(maxWidth: column)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: store.messages.last?.i) { _, _ in scrollDown() }
            .onChange(of: store.live?.text.count) { _, _ in scrollDown(animated: false) }
            .onChange(of: store.live?.tools.count) { _, _ in scrollDown() }
            .onChange(of: store.lastError) { _, _ in scrollDown() }
            .onAppear { composerFocused = true }
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        switch row {
        case .user(let m): UserBubble(message: m)
        case .pith(let m): PithReply(message: m, thought: store.thoughts[m.i])
        case .activity(let ms): ActivityRow(messages: ms)
        case .work(let m): WorkCard(message: m)
        case .note(let m): NoteRow(message: m)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        store.send(text: text)
    }

    /// Waits a frame so the new row is laid out before scrolling to it.
    private func scrollDown(animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.smooth(duration: 0.3)) { position.scrollTo(edge: .bottom) }
            } else {
                position.scrollTo(edge: .bottom)
            }
        }
    }
}

struct Composer: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let busy: Bool
    let send: () -> Void
    let stop: () -> Void

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Escreva para o Pith…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .focused(focused)
                .padding(.vertical, 8)
                .padding(.leading, 6)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
                    if canSend { send() }
                    return .handled
                }

            if busy && !canSend {
                Button(action: stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Parar")
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.heartwood)
                .disabled(!canSend)
                .help(busy ? "Enviar enquanto o Pith trabalha" : "Enviar")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .animation(.smooth(duration: 0.2), value: busy)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label {
            Text(message).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}
