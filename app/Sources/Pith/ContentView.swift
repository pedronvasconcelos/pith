import SwiftUI

struct ContentView: View {
    @Environment(ChatStore.self) private var store
    @AppStorage("showMemory") private var showMemory = true

    var body: some View {
        Group {
            switch store.connection {
            case .starting:
                StartingView()
            case .failed(let message):
                FailureView(message: message) { store.restart() }
            case .connected:
                if store.messages.isEmpty && store.live == nil {
                    EmptyChatView()
                } else {
                    ChatView()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .inspector(isPresented: $showMemory) {
            StrataInspector()
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    RingsLogo(rings: 7, lineWidth: 1).frame(width: 20, height: 20)
                    Text("Pith").font(.headline)
                }
                .padding(.horizontal, 6)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .status) {
                StatusPill()
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth) { showMemory.toggle() }
                } label: {
                    Label("Memória", systemImage: "square.stack.3d.down.right")
                }
                .help(showMemory ? "Ocultar memória" : "Mostrar memória")
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
        .navigationTitle("")
    }
}

/// One quiet line about what the core is doing.
struct StatusPill: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            if store.stats.offline {
                Image(systemName: "wifi.slash")
                Text("Offline")
            } else if store.busy {
                ProgressView().controlSize(.mini)
                Text("Respondendo")
            } else if store.stats.pending > 0 {
                ProgressView().controlSize(.mini)
                Text("Condensando \(store.stats.pending)")
            } else {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(modelName(store.stats.model))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .animation(.smooth, value: store.busy)
    }

    private func modelName(_ id: String) -> String {
        switch id {
        case "claude-opus-5-5": "Opus 5.5"
        case "claude-sonnet-5-5": "Sonnet 5.5"
        case "claude-fable-5-1": "Fable 5.1"
        default: id
        }
    }
}

struct EmptyChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let starters = [
        "O que você consegue fazer no meu Mac?",
        "Lembre: prefiro respostas curtas",
        "Organize meus Downloads",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                RingsLogo(rings: 10, lineWidth: 1.6, animated: true)
                    .frame(width: 132, height: 132)
                VStack(spacing: 8) {
                    Text("Uma conversa. Para sempre.")
                        .font(Theme.serif)
                    Text("Tudo o que vocês conversarem fica guardado, em camadas.\nComece por qualquer coisa.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if store.stats.offline {
                    OfflineNotice()
                }
            }
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(starters, id: \.self) { s in
                        Button(s) { store.send(text: s) }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                }
                Composer(draft: $draft, focused: $focused, busy: store.busy, send: {
                    let t = draft; draft = ""; store.send(text: t)
                }, stop: store.cancel)
                .frame(maxWidth: 720)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .onAppear { focused = true }
    }
}

struct OfflineNotice: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(Theme.heartwood)
            Text("Sem chave da API, o Pith roda em modo offline.")
            SettingsLink { Text("Adicionar chave").fontWeight(.semibold) }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.heartwood)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

struct StartingView: View {
    var body: some View {
        VStack(spacing: 16) {
            RingsLogo(rings: 8, lineWidth: 1.4, animated: true).frame(width: 64, height: 64)
            Text("Abrindo a memória…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("O Pith não conseguiu iniciar", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).textSelection(.enabled)
        } actions: {
            Button("Tentar de novo", action: retry).buttonStyle(.glassProminent).tint(Theme.heartwood)
        }
    }
}
