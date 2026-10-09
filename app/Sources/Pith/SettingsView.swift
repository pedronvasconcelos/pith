import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @AppStorage("model") private var model = "claude-opus-5-5"
    @AppStorage("effort") private var effort = "high"
    @AppStorage("workspace") private var workspace = NSHomeDirectory()
    @State private var key = ""
    @State private var hasKey = Keychain.apiKey != nil
    @State private var dirty = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("Chave da API") {
                        HStack {
                            Label("Guardada no Keychain", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Button("Remover") {
                                Keychain.apiKey = nil
                                hasKey = false
                                dirty = true
                            }
                        }
                    }
                } else {
                    SecureField("Chave da API", text: $key, prompt: Text("sk-ant-…"))
                    HStack {
                        Text("Fica só no seu Keychain. Crie uma em console.anthropic.com.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Salvar") {
                            Keychain.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            key = ""
                            hasKey = Keychain.apiKey != nil
                            dirty = true
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Conta")
            }

            Section("Modelo") {
                Picker("Conversa", selection: $model) {
                    Text("Claude Opus 5.5").tag("claude-opus-5-5")
                    Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                }
                Picker("Esforço", selection: $effort) {
                    Text("Baixo").tag("low")
                    Text("Médio").tag("medium")
                    Text("Alto").tag("high")
                    Text("Máximo").tag("xhigh")
                }
                .pickerStyle(.segmented)
                LabeledContent("Memória", value: "Claude Haiku 5.5")
            }

            Section("Claude Code") {
                LabeledContent("Pasta de trabalho") {
                    HStack {
                        Text((workspace as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Escolher…", action: chooseWorkspace)
                    }
                }
                Text("O Pith pede sua permissão antes de o Claude Code editar arquivos ou rodar comandos.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dados") {
                LabeledContent("Memória") {
                    Button("Mostrar no Finder") {
                        let url = URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent("Library/Application Support/Pith")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .safeAreaInset(edge: .bottom) {
            if dirty {
                HStack {
                    Text("Aplique para reiniciar o core com as novas opções.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Aplicar") {
                        dirty = false
                        store.restart()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.heartwood)
                }
                .padding(16)
            }
        }
        .onChange(of: model) { dirty = true }
        .onChange(of: effort) { dirty = true }
        .onChange(of: workspace) { dirty = true }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: workspace)
        if panel.runModal() == .OK, let url = panel.url { workspace = url.path }
    }
}
