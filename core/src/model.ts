import type Anthropic from "@anthropic-ai/sdk";
import { COMPACT_PROVIDER, FAKE, LINE_MAX } from "./config.ts";
import { cutTask } from "./prompt.ts";
import { claudeAsk } from "./providers/claude.ts";
import { codexAsk } from "./providers/codex.ts";
import { geminiAsk } from "./providers/gemini.ts";
import type { Ask } from "./providers/types.ts";
import type { Stats } from "./stats.ts";
import { bytes, cutBytes, flatten } from "./util.ts";

const ASK: Record<typeof COMPACT_PROVIDER, Ask> = { claude: claudeAsk, gemini: geminiAsk, codex: codexAsk };

/**
 * Writes one tree line. Models can't count bytes, so the task carries a ruler;
 * a reply that is still too long gets up to 5 follow-ups asking to cut, and
 * the shortest attempt wins.
 */
export async function compact(context: Anthropic.TextBlockParam[], task: string, stats: Stats): Promise<string> {
  if (FAKE) return fakeCompact(task);
  const ask = ASK[COMPACT_PROVIDER];
  const turns = [task];
  let best: string | null = null;
  for (let attempt = 0; attempt < 6; attempt++) {
    const line = flatten(await ask(context, turns, stats));
    if (!line) break;
    if (best === null || bytes(line) < bytes(best)) best = line;
    if (bytes(line) <= LINE_MAX) return line;
    turns.push(line, cutTask(cutBytes(line, LINE_MAX)));
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
