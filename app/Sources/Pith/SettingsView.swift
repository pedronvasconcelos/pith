import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @AppStorage("provider") private var provider = "claude"
    @AppStorage("compactProvider") private var compactProvider = "auto"
    @AppStorage("helper") private var helper = "auto"
    @AppStorage("model") private var model = "claude-opus-5-5"
    @AppStorage("geminiModel") private var geminiModel = "gemini-3.8-flash"
    @AppStorage("codexModel") private var codexModel = ""
    @AppStorage("codexWrite") private var codexWrite = false
    @AppStorage("effort") private var effort = "high"
    @AppStorage("workspace") private var workspace = NSHomeDirectory()
    @State private var dirty = false
    @State private var codex = CodexState()

    var body: some View {
        Form {
            Section {
                Picker("Provedor", selection: $provider) {
                    Text("Claude").tag("claude")
                    Text("Gemini").tag("gemini")
                    Text("ChatGPT").tag("codex")
                }
                .pickerStyle(.segmented)

                switch provider {
                case "gemini":
                    Picker("Modelo", selection: $geminiModel) {
                        Text("Gemini 3.8 Flash").tag("gemini-3.8-flash")
                        Text("Gemini 3.1 Pro (preview)").tag("gemini-3.1-pro-preview")
                    }
                    KeyRow(account: .gemini, label: "Chave do Gemini", prompt: "AIza…",
                           hint: "Crie uma em aistudio.google.com.", changed: { dirty = true })
                case "codex":
                    CodexRow(codex: $codex)
                    Picker("Modelo", selection: $codexModel) {
                        Text("Automático").tag("")
                        ForEach(codex.models, id: \.self) { Text($0).tag($0) }
                    }
                default:
                    Picker("Modelo", selection: $model) {
                        Text("Claude Opus 5.5").tag("claude-opus-5-5")
                        Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                    }
                    KeyRow(account: .anthropic, label: "Chave da Anthropic", prompt: "sk-ant-…",
                           hint: "Crie uma em console.anthropic.com.", changed: { dirty = true })
                }

                Picker("Esforço", selection: $effort) {
                    Text("Baixo").tag("low")
                    Text("Médio").tag("medium")
                    Text("Alto").tag("high")
                    Text("Máximo").tag("xhigh")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Conversa")
            } footer: {
                if provider == "codex" {
                    Text("Usa o Codex oficial com o seu login do ChatGPT: o uso conta no seu plano.")
                }
            }

            Section {
                Picker("Condensar com", selection: $compactProvider) {
                    Text("Automático").tag("auto")
                    Text("Claude Haiku 5.5").tag("claude")
                    Text("Gemini 3.5 Flash-Lite").tag("gemini")
                    Text("ChatGPT (Codex)").tag("codex")
                }
                if provider != "claude" && compactProvider != "codex" {
                    KeyRow(account: .anthropic, label: "Chave da Anthropic", prompt: "sk-ant-…",
                           hint: "Opcional: o Haiku condensa a memória rápido e barato.", changed: { dirty = true })
                }
                if provider != "gemini" && compactProvider == "gemini" {
                    KeyRow(account: .gemini, label: "Chave do Gemini", prompt: "AIza…",
                           hint: "Crie uma em aistudio.google.com.", changed: { dirty = true })
                }
            } header: {
                Text("Memória")
            } footer: {
                Text("Automático usa o primeiro disponível: Haiku, depois Gemini Flash-Lite, depois o Codex, que é mais lento.")
            }

            Section {
                Picker("Executar com", selection: $helper) {
                    Text("Automático").tag("auto")
                    Text("Claude Code").tag("claude-code")
                    Text("Codex").tag("codex")
                }
                .disabled(provider == "codex")
                if provider == "codex" || helper == "codex" {
                    Toggle("Permitir que o Codex edite a pasta de trabalho", isOn: $codexWrite)
                }
                LabeledContent("Pasta de trabalho") {
                    HStack {
                        Text((workspace as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Escolher…", action: chooseWorkspace)
                    }
                }
            } header: {
                Text("Ações no Mac")
            } footer: {
                Text(provider == "codex"
                     ? "No ChatGPT, o próprio Codex age no Mac, dentro do sandbox dele."
                     : "O Claude Code pede sua permissão antes de editar arquivos ou rodar comandos. O Codex trabalha sozinho, dentro do sandbox dele.")
            }

            Section {
                ForEach(Integration.allCases) { tool in
                    IntegrationRow(tool: tool)
                }
            } header: {
                Text("Integrações")
            } footer: {
                Text("Deixa outros agentes consultarem sua memória enquanto você trabalha: buscar, ler o resumo e abrir mensagens. Só leitura, nada é escrito no Pith.")
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
        .frame(width: 540)
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
        .task { codex = await CodexState.load() }
        .onChange(of: provider) { dirty = true }
        .onChange(of: compactProvider) { dirty = true }
        .onChange(of: helper) { dirty = true }
        .onChange(of: model) { dirty = true }
        .onChange(of: geminiModel) { dirty = true }
        .onChange(of: codexModel) { dirty = true }
        .onChange(of: codexWrite) { dirty = true }
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

/// One API key: saved to the Keychain, never shown again.
private struct KeyRow: View {
    let account: Keychain.Account
    let label: String
    let prompt: String
    let hint: String
    let changed: () -> Void
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        Group {
            if saved {
                LabeledContent(label) {
                    HStack {
                        Label("No Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Button("Remover") {
                            Keychain[account] = nil
                            saved = false
                            changed()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField(label, text: $key, prompt: Text(prompt))
                    HStack {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Salvar") {
                            Keychain[account] = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            key = ""
                            saved = Keychain[account] != nil
                            changed()
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .onAppear { saved = Keychain[account] != nil }
    }
}

struct CodexState: Equatable {
    var installed = true
    var status: String?
    var models: [String] = []
    var busy = false

    static func load() async -> CodexState {
        await Task.detached {
            CodexState(installed: CodexCLI.path() != nil, status: CodexCLI.status(), models: CodexCLI.models())
        }.value
    }
}

private struct CodexRow: View {
    @Binding var codex: CodexState

    var body: some View {
        LabeledContent("Conta") {
            if !codex.installed {
                Text("Instale o Codex: npm i -g @openai/codex")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if let status = codex.status {
                Label(status.replacingOccurrences(of: "Logged in using", with: "Conectado com"),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button(codex.busy ? "Aguardando o navegador…" : "Entrar com o ChatGPT") {
                    codex.busy = true
                    Task {
                        _ = await CodexCLI.login()
                        codex = await CodexState.load()
                    }
                }
                .disabled(codex.busy)
            }
        }
    }
}

private struct IntegrationRow: View {
    let tool: Integration
    @State private var state: Integration.State?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    switch state {
                    case nil:
                        ProgressView().controlSize(.small)
                    case .missing:
                        Text("Não instalado").foregroundStyle(.tertiary)
                    case .off:
                        Button("Conectar") { change(connect: true) }
                    case .stale:
                        Text("Desatualizado").foregroundStyle(.orange)
                        Button("Reconectar") { change(connect: true) }
                    case .on:
                        Label("Conectado", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Button("Desconectar") { change(connect: false) }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        state = await Task.detached { Integration.Server.current.map { tool.state($0) } ?? .missing }.value
    }

    private func change(connect: Bool) {
        busy = true
        error = nil
        Task {
            let failure: String? = await Task.detached {
                do {
                    guard let server = Integration.Server.current else { return "Node.js não encontrado." }
                    if connect { try tool.connect(server) } else { try tool.disconnect() }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            error = failure
            await refresh()
            busy = false
        }
    }
}
