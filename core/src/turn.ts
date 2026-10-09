import { EventEmitter } from "node:events";
import Anthropic from "@anthropic-ai/sdk";
import type { Agents } from "./agents.ts";
import { FAKE, TURN_EFFORT, TURN_MODEL } from "./config.ts";
import { Memory } from "./memory.ts";
import { anthropic, systemBlocks } from "./model.ts";
import { TOOLS } from "./prompt.ts";
import { parseName } from "./tree.ts";

type Block = Anthropic.Beta.BetaContentBlockParam;
type Param = Anthropic.Beta.BetaMessageParam;

export interface ToolEvent {
  id: string;
  name: string;
  summary: string;
  state: "running" | "done" | "error";
  result?: string;
}

export interface TurnEvents {
  state: [busy: boolean];
  delta: [kind: "text" | "thinking", text: string];
  /** A new assistant block starts: the UI opens a new bubble or thought. */
  block: [kind: "text" | "thinking"];
  tool: [ToolEvent];
  error: [message: string];
}

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
    const view = Memory.mark(blocks, complete) as Block[];

    // Render the view first, then log the new message.
    const texts = this.inbox.splice(0);
    for (const t of texts) this.memory.append("user", t);
    const messages: Param[] = [
      { role: "user", content: [...view, { type: "text", text: `</chat>\n\n${texts.join("\n\n")}` }] },
    ];

    if (FAKE) return this.fakeTurn(texts.join("\n\n"));

    for (;;) {
      if (signal.aborted) return;
      moveFinalMark(messages);
      const stream = anthropic().beta.messages.stream(
        {
          model: TURN_MODEL,
          max_tokens: 64000,
          thinking: { type: "adaptive", display: "summarized" },
          output_config: { effort: TURN_EFFORT },
          system: systemBlocks(),
          tools: TOOLS,
          messages,
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
        },
        { signal },
      );
      for await (const ev of stream) {
        if (ev.type === "content_block_start") {
          if (ev.content_block.type === "text" || ev.content_block.type === "thinking") {
            this.emit("block", ev.content_block.type);
          }
        } else if (ev.type === "content_block_delta") {
          if (ev.delta.type === "text_delta") this.emit("delta", "text", ev.delta.text);
          else if (ev.delta.type === "thinking_delta") this.emit("delta", "thinking", ev.delta.thinking);
        }
      }
      const res = await stream.finalMessage();
      this.memory.stats.add("turns", res.model, res.usage);
      this.memory.emit("changed");

      // Thoughts are shown but never logged.
      const text = res.content
        .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
        .map((b) => b.text)
        .join("")
        .trim();
      if (text) this.memory.append("pith", text);
      if (res.stop_reason === "refusal") {
        this.emit("error", "O modelo recusou esta resposta.");
        return;
      }

      const uses = res.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
      if (res.stop_reason !== "tool_use" || uses.length === 0) return;

      for (const u of uses) this.memory.append("tool", `${u.name}(${JSON.stringify(u.input)})`);
      const results = await Promise.all(uses.map((u) => this.runTool(u, signal)));
      const content: Block[] = uses.map((u, k) => ({
        type: "tool_result",
        tool_use_id: u.id,
        content: results[k].text,
        is_error: results[k].error || undefined,
      }));
      // Messages sent while working are passed in between tool calls.
      const late = this.inbox.splice(0);
      for (const t of late) this.memory.append("user", t);
      if (late.length) {
        content.push({ type: "text", text: `[New message from the user, sent while you worked]\n${late.join("\n\n")}` });
      }
      messages.push({ role: "assistant", content: res.content as Block[] });
      messages.push({ role: "user", content });
    }
  }

  private async runTool(u: Anthropic.Beta.BetaToolUseBlock, signal: AbortSignal): Promise<{ text: string; error: boolean }> {
    const input = u.input as Record<string, unknown>;
    const ev: ToolEvent = { id: u.id, name: u.name, summary: toolSummary(u.name, input), state: "running" };
    this.emit("tool", ev);
    let text: string;
    let error = false;
    try {
      switch (u.name) {
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
          const { name, report } = await this.agents.run(String(input.task), input.cwd as string | undefined, signal);
          text = `[${name}] ${report}`;
          this.memory.append("work", text);
          break;
        }
        default:
          throw new Error(`Unknown tool ${u.name}`);
      }
      if (u.name !== "code") this.memory.append("echo", text);
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
    for (const w of "Modo offline: sem chamadas à API.".split(" ")) {
      this.emit("delta", "thinking", `${w} `);
      await sleep(40);
    }
    const reply = `Recebi: “${text.slice(0, 200)}”.\n\nEstou em **modo offline**, então não chamei nenhum modelo. Adicione sua chave da API nos **Ajustes** (⌘,) para conversar de verdade.`;
    this.emit("block", "text");
    for (const w of reply.split(/(?<= )/)) {
      this.emit("delta", "text", w);
      await sleep(25);
    }
    this.memory.append("pith", reply);
  }
}

/** Keeps one moving cache mark on the last block of the request. */
function moveFinalMark(messages: Param[]): void {
  for (const m of messages) {
    if (typeof m.content === "string") continue;
    const last = m.content.at(-1) as { cache_control?: unknown } | undefined;
    if (last && m !== messages[0]) delete last.cache_control;
  }
  const first = messages[0].content as Block[];
  const firstLast = first.at(-1) as { cache_control?: unknown };
  if (messages.length > 1) delete firstLast.cache_control;
  const tail = messages.at(-1)!.content as Block[];
  (tail.at(-1) as { cache_control?: unknown }).cache_control = { type: "ephemeral" };
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
  if (err instanceof Anthropic.AuthenticationError) return "Chave da API inválida ou ausente. Configure-a nos Ajustes.";
  if (err instanceof Anthropic.RateLimitError) return "Limite de uso atingido. Tente de novo em instantes.";
  if (err instanceof Anthropic.APIError) return `Erro da API (${err.status}): ${err.message}`;
  if (err instanceof Error && /api key|apiKey|authentication/i.test(err.message)) {
    return "Nenhuma chave da API configurada. Adicione-a nos Ajustes.";
  }
  return err instanceof Error ? err.message : String(err);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
