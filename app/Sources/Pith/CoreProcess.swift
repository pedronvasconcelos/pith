import Foundation

/// Starts the TypeScript core as a child process and finds its port.
/// The core exits when our stdin pipe closes, so it never outlives the app.
final class CoreProcess {
    struct Endpoint { let port: Int; let token: String }

    enum Failure: LocalizedError {
        case nodeMissing, coreMissing(String), exited(String)
        var errorDescription: String? {
            switch self {
            case .nodeMissing: "Node.js 24 ou mais novo não foi encontrado. Instale com: brew install node"
            case .coreMissing(let path): "O core do Pith não foi encontrado em \(path)."
            case .exited(let log): "O core parou ao iniciar.\n\(log)"
            }
        }
    }

    private var process: Process?
    private let stdin = Pipe()

    static var coreDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["PITH_CORE_DIR"] { return URL(fileURLWithPath: env) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("core"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("src/main.ts").path) {
            return bundled
        }
        // Development: app/Sources/Pith/CoreProcess.swift -> core/
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("core")
    }

    static func findNode() -> String? {
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(NSHomeDirectory())/.volta/bin/node"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/bin/zsh")
        which.arguments = ["-lc", "command -v node"]
        let out = Pipe()
        which.standardOutput = out
        try? which.run()
        which.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    func start(settings: AppSettings) async throws -> Endpoint {
        stop()
        guard let node = Self.findNode() else { throw Failure.nodeMissing }
        let dir = Self.coreDirectory
        let main = dir.appendingPathComponent("src/main.ts")
        guard FileManager.default.fileExists(atPath: main.path) else { throw Failure.coreMissing(dir.path) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [main.path]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\((node as NSString).deletingLastPathComponent):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let token = ProcessInfo.processInfo.environment["PITH_DEV_TOKEN"] ?? (UUID().uuidString + UUID().uuidString)
        env["PITH_TOKEN"] = token
        env["PITH_MODEL"] = settings.model
        env["PITH_EFFORT"] = settings.effort
        env["PITH_WORKSPACE"] = settings.workspace
        if let key = Keychain.apiKey {
            env["ANTHROPIC_API_KEY"] = key
            env.removeValue(forKey: "PITH_FAKE")
        } else if env["ANTHROPIC_API_KEY"] == nil {
            env["PITH_FAKE"] = "1"
        }
        p.environment = env
        p.standardInput = stdin
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        process = p

        let errLog = LogTail()
        err.fileHandleForReading.readabilityHandler = { h in errLog.append(h.availableData) }

        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            out.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard let line = String(data: data, encoding: .utf8) else { return }
                if let r = line.range(of: "PITH_READY "),
                   let json = line[r.upperBound...].split(separator: "\n").first,
                   let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                   let port = obj["port"] as? Int {
                    once.run { cont.resume(returning: Endpoint(port: port, token: token)) }
                }
            }
            p.terminationHandler = { _ in
                once.run { cont.resume(throwing: Failure.exited(errLog.text)) }
            }
        }
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        p.terminationHandler = nil
        if p.isRunning { p.terminate() }
    }

    deinit { stop() }
}

private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ f: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        f()
    }
}

private final class LogTail: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); if data.count > 8000 { data = data.suffix(8000) }; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(data: data, encoding: .utf8) ?? "" }
}
