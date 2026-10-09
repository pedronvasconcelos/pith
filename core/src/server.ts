import { WebSocketServer, type WebSocket } from "ws";
import type { Agents, PermissionRequest } from "./agents.ts";
import {
  CODEX_MODEL,
  COMPACT_MODEL,
  COMPACT_PROVIDER,
  FAKE,
  GEMINI_COMPACT_MODEL,
  GEMINI_MODEL,
  HELPER,
  PROVIDER,
  TURN_EFFORT,
  TURN_MODEL,
  WORKSPACE,
} from "./config.ts";
import type { Message } from "./log.ts";
import type { Memory } from "./memory.ts";
import { Stats } from "./stats.ts";
import { first, nodeName, parseName, span } from "./tree.ts";
import type { TurnRunner } from "./turn.ts";
import { flatten } from "./util.ts";

type In =
  | { type: "hello" }
  | { type: "send"; text: string }
  | { type: "cancel" }
  | { type: "history"; before: number; limit?: number }
  | { type: "zoom"; id: number; n: number }
  | { type: "branches" }
  | { type: "permission"; id: string; allow: boolean; always?: boolean };

/** Local WebSocket API for the app. Only 127.0.0.1, only with the token. */
export function serve(opts: {
  port: number;
  token: string;
  memory: Memory;
  agents: Agents;
  runner: TurnRunner;
  onListening: (port: number) => void;
}): WebSocketServer {
  const { memory, agents, runner } = opts;
  const clients = new Set<WebSocket>();
  const permissions = new Map<string, PermissionRequest>();

  const wss = new WebSocketServer({
    host: "127.0.0.1",
    port: opts.port,
    maxPayload: 8 * 1024 * 1024,
    verifyClient: ({ req }: { req: import("node:http").IncomingMessage }) => new URL(req.url ?? "/", "http://x").searchParams.get("token") === opts.token,
  });
  wss.on("listening", () => {
    const addr = wss.address();
    opts.onListening(typeof addr === "object" && addr ? addr.port : opts.port);
  });

  const send = (ws: WebSocket, msg: unknown) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
  };
  const broadcast = (msg: unknown) => {
    for (const ws of clients) send(ws, msg);
  };

  const stats = () => {
    const s = memory.stats;
    return {
      type: "stats",
      messages: memory.log.count,
      nodes: memory.tree.size,
      depth: memory.tree.depth,
      viewLines: memory.view.lines.length,
      viewBytes: memory.view.bytes,
      pending: memory.pending,
      costUSD: s.costUSD,
      turnCalls: s.turns.calls,
      compactionCalls: s.compactions.calls,
      cacheHit: Stats.hitRate(s.turns),
      lastTurn: s.last,
      costComplete: s.costComplete,
      provider: PROVIDER,
      model: PROVIDER === "claude" ? TURN_MODEL : PROVIDER === "gemini" ? GEMINI_MODEL : (CODEX_MODEL ?? "codex"),
      effort: TURN_EFFORT,
      compactProvider: COMPACT_PROVIDER,
      compactModel: COMPACT_PROVIDER === "claude" ? COMPACT_MODEL : COMPACT_PROVIDER === "gemini" ? GEMINI_COMPACT_MODEL : (CODEX_MODEL ?? "codex"),
      helper: HELPER,
      workspace: WORKSPACE,
      offline: FAKE,
    };
  };

  const view = () => ({
    type: "view",
    lines: memory.view.lines.map(([l, i]) => ({
      name: nodeName(l, i),
      id: first(l, i),
      n: span(l),
      level: l,
      text: memory.tree.get(l, i) ? flatten(memory.tree.get(l, i)!.text) : null,
    })),
  });

  /**
   * The view as a cut across the tree, plus every ancestor of the cut up to
   * the roots: the complete subtrees of the chat (one per 1-bit of its size).
   */
  const branches = () => {
    const total = memory.log.count;
    const node = (l: number, i: number) => {
      const n = memory.tree.get(l, i);
      return { name: nodeName(l, i), l, i, id: first(l, i), n: span(l), built: !!n, text: n ? flatten(n.text).slice(0, 600) : null };
    };
    const above = new Map<string, [number, number]>();
    for (const [l, i] of memory.view.lines) {
      for (let pl = l + 1, pi = i >> 1; first(pl, pi) + span(pl) <= total; pl++, pi >>= 1) {
        const k = `${pl}:${pi}`;
        if (above.has(k)) break;
        above.set(k, [pl, pi]);
      }
    }
    return {
      type: "branches",
      total,
      cut: memory.view.lines.map(([l, i]) => node(l, i)),
      ancestors: [...above.values()].map(([l, i]) => node(l, i)),
    };
  };

  let timer: NodeJS.Timeout | null = null;
  memory.on("changed", () => {
    timer ??= setTimeout(() => {
      timer = null;
      broadcast(stats());
      broadcast(view());
    }, 250);
  });
  memory.on("node", () => memory.emit("changed"));
  memory.on("message", (m: Message) => broadcast({ type: "message", message: m }));
  runner.on("state", (busy) => broadcast({ type: "state", busy }));
  runner.on("block", (kind) => broadcast({ type: "block", kind }));
  runner.on("delta", (kind, text) => broadcast({ type: "delta", kind, text }));
  runner.on("tool", (tool) => broadcast({ type: "tool", tool }));
  runner.on("error", (message) => broadcast({ type: "error", message }));
  agents.on("progress", (agent, entry) => broadcast({ type: "agent", agent, entry }));
  agents.on("permission", (req) => {
    permissions.set(req.id, req);
    broadcast({ type: "permission", request: req });
  });
  agents.on("permissionResolved", (id) => {
    permissions.delete(id);
    broadcast({ type: "permissionResolved", id });
  });

  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("close", () => clients.delete(ws));
    ws.on("message", (raw) => {
      let msg: In;
      try {
        msg = JSON.parse(String(raw)) as In;
      } catch {
        return;
      }
      switch (msg.type) {
        case "hello":
          send(ws, {
            type: "snapshot",
            messages: memory.log.messages.slice(-200),
            busy: runner.busy,
            permissions: [...permissions.values()],
          });
          send(ws, stats());
          send(ws, view());
          break;
        case "send":
          runner.send(String(msg.text ?? ""));
          break;
        case "cancel":
          runner.cancel();
          break;
        case "history": {
          const end = Math.max(0, Math.min(msg.before, memory.log.count));
          const start = Math.max(0, end - (msg.limit ?? 200));
          send(ws, { type: "history", messages: memory.log.messages.slice(start, end) });
          break;
        }
        case "zoom": {
          const ref = parseName(msg.id, msg.n);
          if (!ref) break;
          const [l, i] = ref;
          const node = memory.tree.get(l, i);
          const children =
            l === 0
              ? []
              : [2 * i, 2 * i + 1]
                  .filter((c) => first(l - 1, c) < memory.log.count)
                  .map((c) => ({
                    name: nodeName(l - 1, c),
                    id: first(l - 1, c),
                    n: span(l - 1),
                    level: l - 1,
                    text: memory.tree.get(l - 1, c) ? flatten(memory.tree.get(l - 1, c)!.text) : null,
                  }));
          send(ws, {
            type: "zoom",
            id: msg.id,
            n: msg.n,
            text: node ? flatten(node.text) : null,
            message: l === 0 ? memory.log.messages[i] ?? null : null,
            children,
          });
          break;
        }
        case "permission":
          agents.answer(msg.id, !!msg.allow, !!msg.always);
          break;
        case "branches":
          send(ws, branches());
          break;
      }
    });
  });

  return wss;
}
