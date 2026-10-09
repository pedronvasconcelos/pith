import Anthropic from "@anthropic-ai/sdk";
import { COMPACT_MODEL, FAKE, LINE_MAX } from "./config.ts";
import { cutTask, SYSTEM, TOOLS } from "./prompt.ts";
import type { Stats } from "./stats.ts";
import { bytes, cutBytes, flatten } from "./util.ts";

let client: Anthropic | null = null;
export function anthropic(): Anthropic {
  client ??= new Anthropic({ maxRetries: 4 });
  return client;
}

export const systemBlocks = (): Anthropic.TextBlockParam[] => [
  { type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } },
];

const textOf = (m: Anthropic.Message): string =>
  m.content
    .filter((b): b is Anthropic.TextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();

/**
 * Writes one tree line. Models can't count bytes, so the task carries a ruler;
 * a reply that is still too long gets up to 5 follow-ups asking to cut, and
 * the shortest attempt wins.
 */
export async function compact(
  context: Anthropic.TextBlockParam[],
  task: string,
  stats: Stats,
): Promise<string> {
  if (FAKE) return fakeCompact(task);
  const messages: Anthropic.MessageParam[] = [
    { role: "user", content: [...context, { type: "text", text: task }] },
  ];
  let best: string | null = null;
  for (let attempt = 0; attempt < 6; attempt++) {
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
    stats.add("compactions", COMPACT_MODEL, res.usage);
    const line = flatten(textOf(res));
    if (line && (best === null || bytes(line) < bytes(best))) best = line;
    if (line && bytes(line) <= LINE_MAX) return line;
    if (res.stop_reason === "refusal" || !line) break;
    messages.push({ role: "assistant", content: res.content });
    messages.push({ role: "user", content: cutTask(cutBytes(line, LINE_MAX)) });
  }
  return cutBytes(best ?? "(compaction failed)", LINE_MAX);
}

/** Offline stand-in: keeps the head of the source. */
function fakeCompact(task: string): string {
  const parts = [...task.matchAll(/<(?:message|line)[^>]*>([\s\S]*?)<\/(?:message|line)>/g)].map((m) =>
    flatten(m[1]),
  );
  const each = Math.floor((LINE_MAX - 8) / Math.max(1, parts.length));
  return cutBytes(parts.map((p) => cutBytes(p, each)).join(" · "), LINE_MAX);
}
