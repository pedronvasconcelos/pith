import Foundation

/// The user's own Codex install: where it is, whether it's signed in, which
/// models their account offers. Pith only ever runs the official CLI.
enum CodexCLI {
    static func path() -> String? {
        let candidates = ["\(NSHomeDirectory())/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        let out = shell("command -v codex").trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    /// "Logged in using ChatGPT", or nil when signed out.
    static func status() -> String? {
        guard let codex = path() else { return nil }
        let out = run(codex, ["login", "status"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.lowercased().contains("logged in") ? out : nil
    }

    /// Model slugs from `codex debug models`, minus internal ones.
    static func models() -> [String] {
        guard let codex = path() else { return [] }
        let out = run(codex, ["debug", "models"])
        let slugs = out.matches(of: /"slug"\s*:\s*"([^"]+)"/).map { String($0.1) }
        var seen = Set<String>()
        return slugs.filter { !$0.contains("review") && !$0.contains("reserve") && seen.insert($0).inserted }
    }

    /// Opens the browser sign-in flow and waits for it.
    static func login() async -> Bool {
        guard let codex = path() else { return false }
        return await Task.detached { run(codex, ["login"]); return status() != nil }.value
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func shell(_ cmd: String) -> String { run("/bin/zsh", ["-lc", cmd]) }
}
