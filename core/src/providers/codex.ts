// Codex through OpenAI's official SDK, on the user's own `codex login`
// (ChatGPT plan or OpenAI key). Codex brings its own tools; Pith's memory
// tools reach it as a local MCP server.
import os from "node:os";
import { fileURLToPath } from "node:url";
import { Codex, type ModelReasoningEffort, type ThreadEvent, type ThreadItem } from "@openai/codex-sdk";
import { CODEX_MODEL, CODEX_PATH, CODEX_SANDBOX, DATA_DIR, TURN_EFFORT, WORKSPACE } from "../config.ts";
import { SYSTEM } from "../prompt.ts";
import type { Ask, TurnContext } from "./types.ts";

const MCP = fileURLToPath(new URL("../mcp.ts", import.meta.url));

let withMemory: Codex | null = null;
let plain: Codex | null = null;
const codex = (memory: boolean): Codex =>
  memory
    ? (withMemory ??= new Codex({
        codexPathOverride: CODEX_PATH,
        config: {
          mcp_servers: {
            // Read-only memory tools: safe to run without asking.
            pith: { command: process.execPath, args: [MCP], env: { PITH_DATA: DATA_DIR }, default_tools_approval_mode: "approve" },
          },
        },
      }))
    : (plain ??= new Codex({ codexPathOverride: CODEX_PATH }));

const effort = (): ModelReasoningEffort => (TURN_EFFORT === "max" ? "xhigh" : TURN_EFFORT);

const NOTE = `# This session

You are running inside Codex, on the user's Mac. There is no code tool: act directly with your own tools. Pith's memory tools (zoom, date, work_log) are the MCP server named pith.`;

export async function codexTurn(ctx: TurnContext): Promise<void> {
  const thread = codex(true).startThread({
    model: CODEX_MODEL,
    workingDirectory: WORKSPACE,
    skipGitRepoCheck: true,
    sandboxMode: CODEX_SANDBOX,
    approvalPolicy: "never",
    modelReasoningEffort: effort(),
  });
  const { events } = await thread.runStreamed(`${SYSTEM}\n\n${NOTE}\n\n${ctx.viewText}\n\n${ctx.text}`, {
    signal: ctx.signal,
  });
  const seen = new Map<string, string>();
  let current: "text" | "thinking" | null = null;
  const stream = (item: ThreadItem & { text: string }, kind: "text" | "thinking") => {
    const before = seen.get(item.id) ?? "";
    if (item.text.length <= before.length) return;
    if (kind !== current) ctx.block((current = kind));
    ctx.delta(kind, item.text.slice(before.length));
    seen.set(item.id, item.text);
  };

  for await (const ev of events as AsyncGenerator<ThreadEvent>) {
    if (ev.type === "turn.failed") throw new Error(ev.error.message);
    if (ev.type === "error") throw new Error(fatal(ev.message));
    if (ev.type === "turn.completed") {
      ctx.stats.add("turns", "codex", {
        input: ev.usage.input_tokens - ev.usage.cached_input_tokens,
        cacheWrite: ev.usage.cache_write_input_tokens ?? 0,
        cacheRead: ev.usage.cached_input_tokens,
        output: ev.usage.output_tokens,
      });
      continue;
    }
    if (ev.type !== "item.started" && ev.type !== "item.updated" && ev.type !== "item.completed") continue;
    const item = ev.item;
    const done = ev.type === "item.completed";
    switch (item.type) {
      case "reasoning":
        stream(item, "thinking");
        break;
      case "agent_message":
        stream(item, "text");
        if (done && item.text.trim()) ctx.log("pith", item.text.trim());
        break;
      case "command_execution":
        if (ev.type === "item.started") {
          ctx.log("tool", `shell(${JSON.stringify(item.command)})`);
          ctx.tool({ id: item.id, name: "shell", summary: item.command, state: "running" });
        } else if (done) {
          ctx.log("echo", item.aggregated_output || `(exit ${item.exit_code ?? "?"})`);
          const failed = item.status === "failed" || (item.exit_code ?? 0) !== 0;
          ctx.tool({ id: item.id, name: "shell", summary: item.command, state: failed ? "error" : "done", result: item.aggregated_output.slice(0, 2000) });
        }
        break;
      case "file_change":
        if (done) {
          const summary = item.changes.map((c) => `${c.kind} ${c.path}`).join(", ");
          ctx.log("tool", `edit(${JSON.stringify(summary)})`);
          ctx.tool({ id: item.id, name: "edit", summary, state: item.status === "failed" ? "error" : "done" });
        }
        break;
      case "mcp_tool_call": {
        const summary = `${item.tool} ${JSON.stringify(item.arguments ?? {})}`;
        if (ev.type === "item.started") {
          ctx.log("tool", `${item.tool}(${JSON.stringify(item.arguments ?? {})})`);
          ctx.tool({ id: item.id, name: item.tool, summary, state: "running" });
        } else if (done) {
          const out = item.error?.message ?? (item.result?.content ?? []).map((c) => ("text" in c ? c.text : "")).join("\n");
          ctx.log("echo", out);
          ctx.tool({ id: item.id, name: item.tool, summary, state: item.error ? "error" : "done", result: out.slice(0, 2000) });
        }
        break;
      }
      case "web_search":
        if (done) {
          ctx.log("tool", `web_search(${JSON.stringify(item.query)})`);
          ctx.tool({ id: item.id, name: "web_search", summary: item.query, state: "done" });
        }
        break;
      case "error":
        // Codex reports warnings (hooks, model metadata) as error items; the turn goes on.
        if (done) console.error(`[codex] ${item.message}`);
        break;
    }
  }
}

/** Compactions on Codex: slower than an API call, but on the user's plan. */
export const codexAsk: Ask = async (context, turns) => {
  const thread = codex(false).startThread({
    model: CODEX_MODEL,
    workingDirectory: os.tmpdir(),
    skipGitRepoCheck: true,
    sandboxMode: "read-only",
    approvalPolicy: "never",
    modelReasoningEffort: "low",
  });
  const history = turns
    .map((t, k) => (k === 0 ? t : k % 2 ? `<your_previous_reply>${t}</your_previous_reply>` : t))
    .join("\n\n");
  const res = await thread.run(`${SYSTEM}\n\n${context.map((b) => b.text).join("\n")}\n</chat>\n\n${history}`);
  return res.finalResponse.trim();
};

/** The `code` tool on Codex: works in the workspace, inside Codex's sandbox. */
export async function codexHelper(
  task: string,
  cwd: string,
  signal: AbortSignal,
  record: (kind: "text" | "tool", text: string) => void,
): Promise<string> {
  const thread = codex(false).startThread({
    model: CODEX_MODEL,
    workingDirectory: cwd,
    skipGitRepoCheck: true,
    sandboxMode: "workspace-write",
    approvalPolicy: "never",
    modelReasoningEffort: effort(),
  });
  const { events } = await thread.runStreamed(
    `${task}\n\nFinish the task, then end with a concise report: what you did, what changed (paths), what failed or was left undone.`,
    { signal },
  );
  let report = "";
  for await (const ev of events) {
    if (ev.type === "turn.failed") throw new Error(ev.error.message);
    if (ev.type !== "item.completed") continue;
    const item = ev.item;
    if (item.type === "agent_message") {
      report = item.text;
      record("text", item.text);
    } else if (item.type === "command_execution") record("tool", `shell ${item.command}`);
    else if (item.type === "file_change") record("tool", item.changes.map((c) => `${c.kind} ${c.path}`).join(", "));
  }
  return report.trim();
}

/** Codex wraps API errors as JSON; keep the human part. */
function fatal(message: string): string {
  try {
    const o = JSON.parse(message) as { error?: { message?: string } };
    return o.error?.message ?? message;
  } catch {
    return message;
  }
}

export function describeCodexError(err: unknown): string | null {
  const msg = err instanceof Error ? err.message : String(err);
  if (/login|unauthori[sz]ed|401|not logged/i.test(msg)) return "O Codex não está conectado. Entre com sua conta do ChatGPT nos Ajustes.";
  if (/model is not supported|model .* not found/i.test(msg)) return `${msg} Escolha outro modelo do Codex nos Ajustes.`;
  if (/ENOENT|spawn/i.test(msg)) return "O Codex não foi encontrado. Instale com: npm i -g @openai/codex";
  return null;
}
