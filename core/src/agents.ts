import { EventEmitter } from "node:events";
import fs from "node:fs";
import path from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { FAKE, HELPER, TOOL_CLIP, WORKSPACE } from "./config.ts";
import { codexHelper } from "./providers/codex.ts";
import { appendLine, clip, readJsonl } from "./util.ts";

export interface AgentEntry {
  date: string;
  kind: "task" | "text" | "tool" | "result" | "error";
  text: string;
}

export interface PermissionRequest {
  id: string;
  agent: string;
  tool: string;
  summary: string;
}

export interface AgentEvents {
  progress: [agent: string, entry: AgentEntry];
  permission: [PermissionRequest];
  permissionResolved: [id: string];
}

/** Claude Code helpers. Each run gets its own log and returns one report. */
export class Agents extends EventEmitter<AgentEvents> {
  private dir: string;
  private pending = new Map<string, (allow: boolean, always: boolean) => void>();
  private alwaysAllowed = new Set<string>();
  private seq: number;

  constructor(dataDir: string) {
    super();
    this.dir = path.join(dataDir, "agents");
    fs.mkdirSync(this.dir, { recursive: true });
    this.seq = fs.readdirSync(this.dir).filter((f) => /^(Code|Codex)-\d+\.jsonl$/.test(f)).length;
  }

  log(name: string): string | null {
    return readAgentLog(this.dir, name);
  }

  answer(id: string, allow: boolean, always = false): void {
    this.pending.get(id)?.(allow, always);
  }

  async run(task: string, cwd: string | undefined, signal: AbortSignal): Promise<{ name: string; report: string }> {
    const name = `${HELPER === "codex" ? "Codex" : "Code"}-${++this.seq}`;
    const file = path.join(this.dir, `${name}.jsonl`);
    const record = (kind: AgentEntry["kind"], text: string) => {
      const e: AgentEntry = { date: new Date().toISOString(), kind, text };
      appendLine(file, e);
      this.emit("progress", name, e);
    };
    record("task", task);

    if (FAKE) {
      record("text", "Running in offline mode; nothing was done.");
      const report = `Offline mode: Claude Code was not run for this task.`;
      record("result", report);
      return { name, report };
    }

    if (HELPER === "codex") {
      try {
        const where = cwd && path.isAbsolute(cwd) ? cwd : WORKSPACE;
        const report = (await codexHelper(task, where, signal, record)) || "(no report)";
        record("result", report);
        return { name, report };
      } catch (err) {
        const text = signal.aborted ? "Cancelled by the user." : `Codex failed: ${(err as Error).message}`;
        record("error", text);
        return { name, report: text };
      }
    }

    const abort = new AbortController();
    signal.addEventListener("abort", () => abort.abort(), { once: true });
    let report = "";
    try {
      for await (const msg of query({
        prompt: task,
        options: {
          cwd: cwd && path.isAbsolute(cwd) ? cwd : WORKSPACE,
          abortController: abort,
          systemPrompt: {
            type: "preset",
            preset: "claude_code",
            append:
              "You are a helper for Pith, the user's assistant. Finish the task, then end with a concise report: what you did, what changed (paths), what failed or was left undone.",
          },
          canUseTool: (tool, input, { signal: s }) => this.ask(name, tool, input, s),
        },
      })) {
        if (msg.type === "assistant") {
          for (const b of msg.message.content) {
            if (b.type === "text" && b.text.trim()) record("text", b.text.trim());
            else if (b.type === "tool_use") record("tool", `${b.name} ${summarize(b.input)}`);
          }
        } else if (msg.type === "result") {
          report = msg.subtype === "success" ? msg.result : `Claude Code stopped: ${msg.subtype}`;
        }
      }
    } catch (err) {
      const text = signal.aborted ? "Cancelled by the user." : `Claude Code failed: ${(err as Error).message}`;
      record("error", text);
      return { name, report: text };
    }
    record("result", report || "(no report)");
    return { name, report: report || "(no report)" };
  }

  private ask(
    agent: string,
    tool: string,
    input: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<{ behavior: "allow"; updatedInput: Record<string, unknown> } | { behavior: "deny"; message: string }> {
    const allow = { behavior: "allow" as const, updatedInput: input };
    if (READ_ONLY.has(tool) || this.alwaysAllowed.has(tool)) return Promise.resolve(allow);
    const id = `${agent}:${Math.random().toString(36).slice(2, 10)}`;
    return new Promise((resolve) => {
      const done = (ok: boolean, always: boolean) => {
        this.pending.delete(id);
        this.emit("permissionResolved", id);
        if (ok && always) this.alwaysAllowed.add(tool);
        resolve(ok ? allow : { behavior: "deny", message: "The user declined this action." });
      };
      this.pending.set(id, done);
      signal.addEventListener("abort", () => done(false, false), { once: true });
      this.emit("permission", { id, agent, tool, summary: summarize(input) });
    });
  }
}

/** A helper run's log, clipped. Helpers are named like Code-3 or Codex-2. */
export function readAgentLog(agentsDir: string, name: string): string | null {
  const file = path.join(agentsDir, `${path.basename(name)}.jsonl`);
  if (!fs.existsSync(file)) return null;
  return clip(
    readJsonl<AgentEntry>(file)
      .map((e) => `[${e.kind}] ${e.text}`)
      .join("\n"),
    TOOL_CLIP,
  );
}

const READ_ONLY = new Set(["Read", "Glob", "Grep", "LS", "WebSearch", "WebFetch", "TodoWrite", "NotebookRead"]);

function summarize(input: unknown): string {
  if (!input || typeof input !== "object") return String(input ?? "");
  const o = input as Record<string, unknown>;
  const main = o.command ?? o.file_path ?? o.path ?? o.url ?? o.pattern ?? o.query ?? o.description;
  const s = typeof main === "string" ? main : JSON.stringify(input);
  return s.length > 300 ? `${s.slice(0, 300)}…` : s;
}
