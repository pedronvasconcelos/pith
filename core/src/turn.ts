import { EventEmitter } from "node:events";
import type { Agents } from "./agents.ts";
import { FAKE, PROVIDER } from "./config.ts";
import { Memory } from "./memory.ts";
import { claudeTurn, describeClaudeError } from "./providers/claude.ts";
import { codexTurn, describeCodexError } from "./providers/codex.ts";
import { describeGeminiError, geminiTurn } from "./providers/gemini.ts";
import type { ToolEvent, TurnContext } from "./providers/types.ts";
import { parseName } from "./tree.ts";

export type { ToolEvent } from "./providers/types.ts";

export interface TurnEvents {
  state: [busy: boolean];
  delta: [kind: "text" | "thinking", text: string];
  /** A new assistant block starts: the UI opens a new bubble or thought. */
  block: [kind: "text" | "thinking"];
  tool: [ToolEvent];
  error: [message: string];
}

const PROVIDERS = { claude: claudeTurn, gemini: geminiTurn, codex: codexTurn };

/**
 * Runs turns. Each turn is a fresh call: [tools][system][view][new message].
 * Nothing carries over between turns except the view.
 */
export class TurnRunner extends EventEmitter<TurnEvents> {
  private inbox: string[] = [];
  private abort: AbortController | null = null;
  busy = false;

  private memory: Memory;
  private agents: Agents;

  constructor(memory: Memory, agents: Agents) {
    super();
    this.memory = memory;
    this.agents = agents;
  }

  send(text: string): void {
    const t = text.trim();
    if (!t) return;
    this.inbox.push(t);
    if (!this.busy) void this.loop();
  }

  cancel(): void {
    this.inbox = [];
    this.abort?.abort();
  }

  private async loop(): Promise<void> {
    this.busy = true;
    this.emit("state", true);
    try {
      while (this.inbox.length) {
        this.abort = new AbortController();
        try {
          await this.turn(this.abort.signal);
        } catch (err) {
          if (!this.abort.signal.aborted) this.emit("error", describe(err));
        }
      }
    } finally {
      this.abort = null;
      this.busy = false;
      this.emit("state", false);
    }
  }

  private async turn(signal: AbortSignal): Promise<void> {
    // Earlier messages must be condensed before the view can be rendered.
    await this.memory.ready();
    const { blocks, complete } = this.memory.blocks(this.memory.view);
    const view = Memory.mark(blocks, complete);
    const viewText = `${blocks.map((b) => b.text).join("\n")}\n</chat>`;

    // Render the view first, then log the new message.
    const texts = this.inbox.splice(0);
    for (const t of texts) this.memory.append("user", t);
    const text = texts.join("\n\n");
    if (FAKE) return this.fakeTurn(text);

    const ctx: TurnContext = {
      view,
      viewText,
      text,
      signal,
      stats: this.memory.stats,
      block: (kind) => this.emit("block", kind),
      delta: (kind, t) => this.emit("delta", kind, t),
      runTool: (id, name, input) => this.runTool(id, name, input, signal),
      tool: (ev) => this.emit("tool", ev),
      log: (kind, t) => {
        this.memory.append(kind, t);
      },
      takeLate: () => {
        const late = this.inbox.splice(0);
        for (const t of late) this.memory.append("user", t);
        return late;
      },
      error: (message) => this.emit("error", message),
    };
    try {
      await PROVIDERS[PROVIDER](ctx);
    } finally {
      this.memory.emit("changed");
    }
  }

  private async runTool(
    id: string,
    name: string,
    input: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<{ text: string; error: boolean }> {
    this.memory.append("tool", `${name}(${JSON.stringify(input)})`);
    const ev: ToolEvent = { id, name, summary: toolSummary(name, input), state: "running" };
    this.emit("tool", ev);
    let text: string;
    let error = false;
    try {
      switch (name) {
        case "zoom": {
          const ref = parseName(Number(input.id), Number(input.n));
          if (!ref) throw new Error("Not a line: n must be a power of two and id a multiple of n.");
          text = this.memory.zoom(ref[0], ref[1]);
          break;
        }
        case "work_log":
          text = this.agents.log(String(input.name)) ?? "No such helper log.";
          break;
        case "date": {
          const m = this.memory.log.messages[Number(input.id)];
          if (!m) throw new Error("No such message.");
          text = new Date(m.date).toString();
          break;
        }
        case "code": {
          const { name: helper, report } = await this.agents.run(String(input.task), input.cwd as string | undefined, signal);
          text = `[${helper}] ${report}`;
          this.memory.append("work", text);
          break;
        }
        default:
          throw new Error(`Unknown tool ${name}`);
      }
      if (name !== "code") this.memory.append("echo", text);
    } catch (err) {
      text = (err as Error).message;
      error = true;
      this.memory.append("echo", `error: ${text}`);
    }
    this.emit("tool", { ...ev, state: error ? "error" : "done", result: text.slice(0, 2000) });
    return { text, error };
  }

  private async fakeTurn(text: string): Promise<void> {
    this.emit("block", "thinking");
    for (const w of "Modo offline: sem chamadas a nenhum modelo.".split(" ")) {
      this.emit("delta", "thinking", `${w} `);
      await sleep(40);
    }
    const reply = `Recebi: “${text.slice(0, 200)}”.\n\nEstou em **modo offline**, então não chamei nenhum modelo. Escolha um provedor nos **Ajustes** (⌘,): Claude ou Gemini com uma chave, ou o ChatGPT pelo Codex.`;
    this.emit("block", "text");
    for (const w of reply.split(/(?<= )/)) {
      this.emit("delta", "text", w);
      await sleep(25);
    }
    this.memory.append("pith", reply);
  }
}

function toolSummary(name: string, input: Record<string, unknown>): string {
  switch (name) {
    case "zoom":
      return `${input.id}+${input.n}`;
    case "date":
      return `#${input.id}`;
    case "work_log":
      return String(input.name);
    case "code":
      return String(input.task).slice(0, 240);
    default:
      return JSON.stringify(input).slice(0, 240);
  }
}

function describe(err: unknown): string {
  const known = describeClaudeError(err) ?? describeGeminiError(err) ?? (PROVIDER === "codex" ? describeCodexError(err) : null);
  if (known) return known;
  if (err instanceof Error && /api key|apiKey|authentication/i.test(err.message)) {
    return "Falta a chave da API do provedor escolhido. Adicione-a nos Ajustes.";
  }
  return err instanceof Error ? err.message : String(err);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
