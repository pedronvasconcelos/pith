import Foundation

/// Lets other agents consult Pith's memory through its read-only MCP server.
/// Each tool is registered with its own official mechanism, and only when the
/// user turns it on.
enum Integration: String, CaseIterable, Identifiable {
    case claudeCode, cursor, codex
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }

    enum State: Equatable {
        case missing          // the tool isn't installed
        case off              // installed, Pith not registered
        case on               // registered with this copy of Pith
        case stale            // registered with an old path (the app moved)
    }

    /// node + core/src/mcp.ts of this copy of the app, and where the memory lives.
    struct Server {
        let node: String
        let script: String
        let data: String

        static var current: Server? {
            guard let node = CoreProcess.findNode() else { return nil }
            let script = CoreProcess.coreDirectory.appendingPathComponent("src/mcp.ts").path
            let data = ProcessInfo.processInfo.environment["PITH_DATA"]
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Pith").path
            return Server(node: node, script: script, data: data)
        }
    }

    private static let name = "pith"
    private static var cursorConfig: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cursor/mcp.json")
    }

    private var cli: String? {
        switch self {
        case .claudeCode: Self.find("claude")
        case .codex: CodexCLI.path()
        case .cursor: nil
        }
    }

    func state(_ server: Server) -> State {
        switch self {
        case .cursor:
            guard FileManager.default.fileExists(atPath: Self.cursorConfig.deletingLastPathComponent().path) else { return .missing }
            guard let entry = Self.readCursor()["mcpServers"].flatMap({ ($0 as? [String: Any])?[Self.name] }) as? [String: Any]
            else { return .off }
            return ((entry["args"] as? [String]) ?? []).contains(server.script) ? .on : .stale
        case .claudeCode, .codex:
            guard let cli else { return .missing }
            let out = CodexCLI.run(cli, ["mcp", "get", Self.name])
            if out.isEmpty || out.localizedCaseInsensitiveContains("not found") || out.localizedCaseInsensitiveContains("no mcp server") {
                return .off
            }
            return out.contains(server.script) ? .on : .stale
        }
    }

    func connect(_ server: Server) throws {
        switch self {
        case .cursor:
            var config = Self.readCursor()
            var servers = config["mcpServers"] as? [String: Any] ?? [:]
            servers[Self.name] = ["command": server.node, "args": [server.script], "env": ["PITH_DATA": server.data]]
            config["mcpServers"] = servers
            try Self.writeCursor(config)
        case .claudeCode:
            guard let cli else { return }
            CodexCLI.run(cli, ["mcp", "remove", "--scope", "user", Self.name])
            CodexCLI.run(cli, ["mcp", "add", "--scope", "user", Self.name, "-e", "PITH_DATA=\(server.data)", "--", server.node, server.script])
        case .codex:
            guard let cli else { return }
            CodexCLI.run(cli, ["mcp", "remove", Self.name])
            CodexCLI.run(cli, ["mcp", "add", Self.name, "--env", "PITH_DATA=\(server.data)", "--", server.node, server.script])
        }
    }

    func disconnect() throws {
        switch self {
        case .cursor:
            var config = Self.readCursor()
            var servers = config["mcpServers"] as? [String: Any] ?? [:]
            servers.removeValue(forKey: Self.name)
            config["mcpServers"] = servers
            try Self.writeCursor(config)
        case .claudeCode:
            if let cli { CodexCLI.run(cli, ["mcp", "remove", "--scope", "user", Self.name]) }
        case .codex:
            if let cli { CodexCLI.run(cli, ["mcp", "remove", Self.name]) }
        }
    }

    // MARK: Cursor's ~/.cursor/mcp.json, edited without touching other servers.

    private static func readCursor() -> [String: Any] {
        guard let data = try? Data(contentsOf: cursorConfig),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func writeCursor(_ config: [String: Any]) throws {
        let fm = FileManager.default
        let backup = cursorConfig.appendingPathExtension("before-pith")
        if fm.fileExists(atPath: cursorConfig.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: cursorConfig, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: cursorConfig, options: .atomic)
    }

    private static func find(_ tool: String) -> String? {
        let candidates = ["\(NSHomeDirectory())/.local/bin/\(tool)", "/opt/homebrew/bin/\(tool)", "/usr/local/bin/\(tool)"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        let out = CodexCLI.run("/bin/zsh", ["-lc", "command -v \(tool)"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
}
