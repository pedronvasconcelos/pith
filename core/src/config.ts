import os from "node:os";
import path from "node:path";

export const DATA_DIR =
  process.env.PITH_DATA ?? path.join(os.homedir(), "Library", "Application Support", "Pith");

export const FAKE = process.env.PITH_FAKE === "1";

/** Max bytes of one tree line. */
export const LINE_MAX = 512;
/** The chat view sawtooths between these sizes. */
export const VIEW_HIGH = Number(process.env.PITH_VIEW_HIGH ?? 128_000);
export const VIEW_LOW = Number(process.env.PITH_VIEW_LOW ?? 64_000);
/** Compactions read a view merged further, so they share caches with each other. */
export const COMPACT_VIEW_HIGH = 32_000;
export const COMPACT_VIEW_LOW = 16_000;
/** View lines per cache block. */
export const BLOCK_LINES = 4;
/** Tool output is clipped to head + tail of this many chars. */
export const TOOL_CLIP = 30_000;
/** Longer texts are split across consecutive messages of this many chars. */
export const MESSAGE_CHUNK = 30_000;

export type Provider = "claude" | "gemini" | "codex";
const provider = (v: string | undefined, d: Provider): Provider =>
  v === "claude" || v === "gemini" || v === "codex" ? v : d;

/** Who writes the turns, who condenses the memory, who acts on the Mac. */
export const PROVIDER = provider(process.env.PITH_PROVIDER, "claude");
export const COMPACT_PROVIDER = provider(process.env.PITH_COMPACT_PROVIDER, PROVIDER);
export const HELPER: "claude-code" | "codex" = process.env.PITH_HELPER === "codex" ? "codex" : "claude-code";

export const TURN_MODEL = process.env.PITH_MODEL ?? "claude-opus-5-5";
export const TURN_EFFORT = (process.env.PITH_EFFORT ?? "high") as
  | "low" | "medium" | "high" | "xhigh" | "max";
export const COMPACT_MODEL = process.env.PITH_COMPACT_MODEL ?? "claude-haiku-5-5";
export const GEMINI_MODEL = process.env.PITH_GEMINI_MODEL ?? "gemini-3.8-flash";
export const GEMINI_COMPACT_MODEL = process.env.PITH_GEMINI_COMPACT_MODEL ?? "gemini-3.5-flash-lite";
/** Codex uses the user's own `codex login`; unset model means Codex's default. */
export const CODEX_MODEL = process.env.PITH_CODEX_MODEL || undefined;
export const CODEX_PATH = process.env.PITH_CODEX_PATH || undefined;
export const CODEX_SANDBOX = (process.env.PITH_CODEX_SANDBOX ?? "read-only") as
  | "read-only" | "workspace-write";
export const WORKSPACE = process.env.PITH_WORKSPACE ?? os.homedir();

/** Concurrent compaction calls. Codex runs a process per call, so fewer. */
export const COMPACT_CONCURRENCY = COMPACT_PROVIDER === "codex" ? 2 : 8;
