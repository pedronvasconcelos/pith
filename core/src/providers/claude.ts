import Anthropic from "@anthropic-ai/sdk";
import { COMPACT_MODEL, TURN_EFFORT, TURN_MODEL } from "../config.ts";
import { SYSTEM, TOOLS } from "../prompt.ts";
import type { Ask, TurnContext } from "./types.ts";

type Block = Anthropic.Beta.BetaContentBlockParam;
type Param = Anthropic.Beta.BetaMessageParam;

let client: Anthropic | null = null;
const anthropic = (): Anthropic => (client ??= new Anthropic({ maxRetries: 4 }));

const systemBlocks = (): Anthropic.TextBlockParam[] => [
  { type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } },
];

/** [tools][system][view in 4-line blocks][new message], with a tool loop. */
export async function claudeTurn(ctx: TurnContext): Promise<void> {
  const messages: Param[] = [
    { role: "user", content: [...(ctx.view as Block[]), { type: "text", text: `</chat>\n\n${ctx.text}` }] },
  ];
  for (;;) {
    if (ctx.signal.aborted) return;
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
      { signal: ctx.signal },
    );
    for await (const ev of stream) {
      if (ev.type === "content_block_start") {
        if (ev.content_block.type === "text" || ev.content_block.type === "thinking") ctx.block(ev.content_block.type);
      } else if (ev.type === "content_block_delta") {
        if (ev.delta.type === "text_delta") ctx.delta("text", ev.delta.text);
        else if (ev.delta.type === "thinking_delta") ctx.delta("thinking", ev.delta.thinking);
      }
    }
    const res = await stream.finalMessage();
    ctx.stats.add("turns", res.model, {
      input: res.usage.input_tokens,
      cacheWrite: res.usage.cache_creation_input_tokens ?? 0,
      cacheRead: res.usage.cache_read_input_tokens ?? 0,
      output: res.usage.output_tokens,
    });

    // Thoughts are shown but never logged.
    const text = res.content
      .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
      .map((b) => b.text)
      .join("")
      .trim();
    if (text) ctx.log("pith", text);
    if (res.stop_reason === "refusal") return ctx.error("O modelo recusou esta resposta.");

    const uses = res.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
    if (res.stop_reason !== "tool_use" || uses.length === 0) return;

    const results = await Promise.all(uses.map((u) => ctx.runTool(u.id, u.name, u.input as Record<string, unknown>)));
    const content: Block[] = uses.map((u, k) => ({
      type: "tool_result",
      tool_use_id: u.id,
      content: results[k].text,
      is_error: results[k].error || undefined,
    }));
    // Messages sent while working are passed in between tool calls.
    const late = ctx.takeLate();
    if (late.length) {
      content.push({ type: "text", text: `[New message from the user, sent while you worked]\n${late.join("\n\n")}` });
    }
    messages.push({ role: "assistant", content: res.content as Block[] });
    messages.push({ role: "user", content });
  }
}

/** Keeps one moving cache mark on the last block of the request. */
function moveFinalMark(messages: Param[]): void {
  for (const m of messages.slice(1)) {
    if (typeof m.content !== "string") delete (m.content.at(-1) as { cache_control?: unknown }).cache_control;
  }
  const firstLast = (messages[0].content as Block[]).at(-1) as { cache_control?: unknown };
  if (messages.length > 1) delete firstLast.cache_control;
  const tail = messages.at(-1)!.content as Block[];
  (tail.at(-1) as { cache_control?: unknown }).cache_control = { type: "ephemeral" };
}

export const claudeAsk: Ask = async (context, turns, stats) => {
  const messages: Anthropic.MessageParam[] = turns.map((t, k) =>
    k === 0
      ? { role: "user", content: [...context, { type: "text", text: t }] }
      : { role: k % 2 ? "assistant" : "user", content: t },
  );
  const res = await anthropic().messages.create({
    model: COMPACT_MODEL,
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    output_config: { effort: "xhigh" },
    system: systemBlocks(),
    tools: TOOLS,
    tool_choice: { type: "none" },
    messages,
  });
  stats.add("compactions", COMPACT_MODEL, {
    input: res.usage.input_tokens,
    cacheWrite: res.usage.cache_creation_input_tokens ?? 0,
    cacheRead: res.usage.cache_read_input_tokens ?? 0,
    output: res.usage.output_tokens,
  });
  if (res.stop_reason === "refusal") return "";
  return res.content
    .filter((b): b is Anthropic.TextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
};

export function describeClaudeError(err: unknown): string | null {
  if (err instanceof Anthropic.AuthenticationError) return "Chave da API da Anthropic inválida ou ausente. Confira nos Ajustes.";
  if (err instanceof Anthropic.RateLimitError) return "Limite de uso da Anthropic atingido. Tente de novo em instantes.";
  if (err instanceof Anthropic.APIError) return `Erro da API da Anthropic (${err.status}): ${err.message}`;
  return null;
}
