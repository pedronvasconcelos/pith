import type Anthropic from "@anthropic-ai/sdk";
import type { Kind } from "../log.ts";
import type { Stats } from "../stats.ts";

export interface ToolEvent {
  id: string;
  name: string;
  summary: string;
  state: "running" | "done" | "error";
  result?: string;
}

/** What a provider gets to run one turn. Nothing else carries over. */
export interface TurnContext {
  /** The view as cache-marked blocks, "<chat>" through the last line. */
  view: Anthropic.TextBlockParam[];
  /** The same view as one string, "<chat>…</chat>". */
  viewText: string;
  /** The new message(s). */
  text: string;
  signal: AbortSignal;
  stats: Stats;
  block(kind: "text" | "thinking"): void;
  delta(kind: "text" | "thinking", text: string): void;
  /** Logs a call and its result, and runs it (zoom, date, work_log, code). */
  runTool(id: string, name: string, input: Record<string, unknown>): Promise<{ text: string; error: boolean }>;
  /** Reports a tool the provider ran itself (Codex runs its own). */
  tool(ev: ToolEvent): void;
  log(kind: Kind, text: string): void;
  /** Messages the user sent while the turn ran; already logged. */
  takeLate(): string[];
  error(message: string): void;
}

/**
 * One compaction call: `turns` alternate user/assistant, starting with the
 * task. The provider puts `context` (the compaction view) before it.
 */
export type Ask = (context: Anthropic.TextBlockParam[], turns: string[], stats: Stats) => Promise<string>;
