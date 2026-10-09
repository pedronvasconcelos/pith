import Foundation
import Observation
import SwiftUI

struct AppSettings: Equatable {
    var model: String
    var effort: String
    var workspace: String

    static var current: AppSettings {
        let d = UserDefaults.standard
        return AppSettings(
            model: d.string(forKey: "model") ?? "claude-opus-5-5",
            effort: d.string(forKey: "effort") ?? "high",
            workspace: d.string(forKey: "workspace") ?? NSHomeDirectory()
        )
    }
}

/// One live helper run, shown as a card while it works.
struct AgentRun: Identifiable, Hashable {
    let id: String
    var task: String = ""
    var entries: [AgentEntry] = []
    var done = false
}

/// The turn being written right now. Thoughts are never logged, so the store
/// keeps them for this session only, attached to the reply they led to.
struct LiveTurn {
    var thinking = ""
    var text = ""
    var tools: [ToolEvent] = []
}

enum Connection: Equatable {
    case starting, connected, failed(String)
}

@MainActor
@Observable
final class ChatStore {
    var messages: [LogMessage] = []
    var live: LiveTurn?
    var thoughts: [Int: String] = [:]
    var agents: [String: AgentRun] = [:]
    var permissions: [PermissionRequest] = []
    var stats = CoreStats()
    var view: [ViewLine] = []
    var busy = false
    var connection: Connection = .starting
    var lastError: String?
    var zoom: ZoomResult?
    var hasOlder: Bool { (messages.first?.i ?? 0) > 0 }

    private let core = CoreProcess()
    private var socket: URLSessionWebSocketTask?
    private var settings = AppSettings.current

    func start() async {
        connection = .starting
        settings = AppSettings.current
        do {
            let ep = try await core.start(settings: settings)
            connect(ep)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    func restart() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        live = nil
        busy = false
        Task { await start() }
    }

    func stop() {
        socket?.cancel(with: .goingAway, reason: nil)
        core.stop()
    }

    private func connect(_ ep: CoreProcess.Endpoint) {
        let url = URL(string: "ws://127.0.0.1:\(ep.port)/?token=\(ep.token)")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        socket = task
        task.resume()
        send(["type": "hello"])
        connection = .connected
        receive(task)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let msg):
                    let data: Data? = switch msg {
                    case .string(let s): Data(s.utf8)
                    case .data(let d): d
                    @unknown default: nil
                    }
                    if let data, let ev = CoreEvent.decode(data) { self.handle(ev) }
                    self.receive(task)
                case .failure(let err):
                    self.connection = .failed("Conexão com o core perdida: \(err.localizedDescription)")
                }
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(s)) { _ in }
    }

    // MARK: Actions

    func send(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastError = nil
        send(["type": "send", "text": t])
    }

    func cancel() { send(["type": "cancel"]) }

    func loadOlder() {
        guard let first = messages.first?.i, first > 0 else { return }
        send(["type": "history", "before": first, "limit": 200])
    }

    func open(_ line: ViewLine) { send(["type": "zoom", "id": line.id, "n": line.n]) }
    func open(id: Int, n: Int) { send(["type": "zoom", "id": id, "n": n]) }

    func answer(_ req: PermissionRequest, allow: Bool, always: Bool = false) {
        permissions.removeAll { $0.id == req.id }
        send(["type": "permission", "id": req.id, "allow": allow, "always": always])
    }

    // MARK: Events

    private func handle(_ ev: CoreEvent) {
        switch ev {
        case .snapshot(let msgs, let busy, let perms):
            messages = msgs
            self.busy = busy
            permissions = perms
        case .message(let m):
            guard !messages.contains(where: { $0.i == m.i }) else { return }
            if m.kind == "pith", let l = live {
                if !l.thinking.isEmpty { thoughts[m.i] = l.thinking }
                live?.thinking = ""
                live?.text = ""
            }
            withAnimation(.smooth(duration: 0.25)) { messages.append(m) }
        case .history(let older):
            let known = Set(messages.map(\.i))
            messages.insert(contentsOf: older.filter { !known.contains($0.i) }, at: 0)
        case .stats(let s):
            stats = s
        case .view(let lines):
            view = lines
        case .state(let b):
            withAnimation(.smooth) {
                busy = b
                live = b ? LiveTurn() : nil
                if !b { for k in agents.keys { agents[k]?.done = true } }
            }
        case .block(let kind):
            if live == nil { live = LiveTurn() }
            if kind == "thinking", let t = live?.thinking, !t.isEmpty { live?.thinking += "\n\n" }
        case .delta(let kind, let text):
            if live == nil { live = LiveTurn() }
            if kind == "thinking" { live?.thinking += text } else { live?.text += text }
        case .tool(let t):
            if live == nil { live = LiveTurn() }
            if let k = live?.tools.firstIndex(where: { $0.id == t.id }) { live?.tools[k] = t } else { live?.tools.append(t) }
        case .agent(let name, let entry):
            var run = agents[name] ?? AgentRun(id: name)
            if entry.kind == "task" { run.task = entry.text } else { run.entries.append(entry) }
            if entry.kind == "result" || entry.kind == "error" { run.done = true }
            agents[name] = run
        case .permission(let req):
            if !permissions.contains(req) { permissions.append(req) }
        case .permissionResolved(let id):
            permissions.removeAll { $0.id == id }
        case .zoom(let z):
            zoom = z
        case .error(let msg):
            lastError = msg
        }
    }
}
