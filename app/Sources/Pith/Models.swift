import Foundation

struct LogMessage: Codable, Identifiable, Hashable {
    let i: Int
    let kind: String
    let text: String
    let size: Int
    let date: String
    var id: Int { i }

    var timestamp: Date? { ISO8601DateFormatter.withFractions.date(from: date) }
}

struct CoreStats: Codable {
    var messages = 0
    var nodes = 0
    var depth = 0
    var viewLines = 0
    var viewBytes = 0
    var pending = 0
    var costUSD = 0.0
    var turnCalls = 0
    var compactionCalls = 0
    var cacheHit = 0.0
    var model = ""
    var effort = ""
    var compactModel = ""
    var workspace = ""
    var offline = false
    var provider: String? = nil
    var compactProvider: String? = nil
    var helper: String? = nil
    var costComplete: Bool? = nil
}

struct ViewLine: Codable, Identifiable, Hashable {
    let name: String
    let id: Int
    let n: Int
    let level: Int
    let text: String?
}

struct ToolEvent: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let state: String
    let result: String?
}

struct AgentEntry: Codable, Hashable {
    let date: String
    let kind: String
    let text: String
}

struct PermissionRequest: Codable, Identifiable, Hashable {
    let id: String
    let agent: String
    let tool: String
    let summary: String
}

struct ZoomResult: Codable {
    let id: Int
    let n: Int
    let text: String?
    let message: LogMessage?
    let children: [ViewLine]
}

/// A node of the memory tree, for the Branches window.
struct BranchNode: Codable, Identifiable, Hashable {
    let name: String
    let l: Int
    let i: Int
    let id: Int
    let n: Int
    let built: Bool
    let text: String?
    var key: String { "\(l):\(i)" }
}

struct Branches: Codable {
    let total: Int
    let cut: [BranchNode]
    let ancestors: [BranchNode]
}

/// Everything the core can send. Decoded by its `type`.
enum CoreEvent {
    case snapshot(messages: [LogMessage], busy: Bool, permissions: [PermissionRequest])
    case message(LogMessage)
    case history([LogMessage])
    case stats(CoreStats)
    case view([ViewLine])
    case state(busy: Bool)
    case block(kind: String)
    case delta(kind: String, text: String)
    case tool(ToolEvent)
    case agent(name: String, entry: AgentEntry)
    case permission(PermissionRequest)
    case permissionResolved(id: String)
    case zoom(ZoomResult)
    case branches(Branches)
    case error(String)

    static func decode(_ data: Data) -> CoreEvent? {
        let d = JSONDecoder()
        guard let head = try? d.decode(Head.self, from: data) else { return nil }
        switch head.type {
        case "snapshot":
            guard let s = try? d.decode(Snapshot.self, from: data) else { return nil }
            return .snapshot(messages: s.messages, busy: s.busy, permissions: s.permissions)
        case "message": return (try? d.decode(One<LogMessage>.self, from: data)).map { .message($0.message) }
        case "history": return (try? d.decode(Many.self, from: data)).map { .history($0.messages) }
        case "stats": return (try? d.decode(CoreStats.self, from: data)).map { .stats($0) }
        case "view": return (try? d.decode(Lines.self, from: data)).map { .view($0.lines) }
        case "state": return (try? d.decode(Busy.self, from: data)).map { .state(busy: $0.busy) }
        case "block": return (try? d.decode(Kind.self, from: data)).map { .block(kind: $0.kind) }
        case "delta": return (try? d.decode(Delta.self, from: data)).map { .delta(kind: $0.kind, text: $0.text) }
        case "tool": return (try? d.decode(Tool.self, from: data)).map { .tool($0.tool) }
        case "agent": return (try? d.decode(Agent.self, from: data)).map { .agent(name: $0.agent, entry: $0.entry) }
        case "permission": return (try? d.decode(Perm.self, from: data)).map { .permission($0.request) }
        case "permissionResolved": return (try? d.decode(Ident.self, from: data)).map { .permissionResolved(id: $0.id) }
        case "zoom": return (try? d.decode(ZoomResult.self, from: data)).map { .zoom($0) }
        case "branches": return (try? d.decode(Branches.self, from: data)).map { .branches($0) }
        case "error": return (try? d.decode(Err.self, from: data)).map { .error($0.message) }
        default: return nil
        }
    }

    private struct Head: Decodable { let type: String }
    private struct Snapshot: Decodable { let messages: [LogMessage]; let busy: Bool; let permissions: [PermissionRequest] }
    private struct One<T: Decodable>: Decodable { let message: T }
    private struct Many: Decodable { let messages: [LogMessage] }
    private struct Lines: Decodable { let lines: [ViewLine] }
    private struct Busy: Decodable { let busy: Bool }
    private struct Kind: Decodable { let kind: String }
    private struct Delta: Decodable { let kind: String; let text: String }
    private struct Tool: Decodable { let tool: ToolEvent }
    private struct Agent: Decodable { let agent: String; let entry: AgentEntry }
    private struct Perm: Decodable { let request: PermissionRequest }
    private struct Ident: Decodable { let id: String }
    private struct Err: Decodable { let message: String }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
