import os from "node:os";
import path from "node:path";

export const DATA_DIR =
  process.env.PITH_DATA ?? path.join(os.homedir(), "Library", "Application Support", "Pith");

export const FAKE = process.env.PITH_FAKE === "1";

/** Max bytes of one tree line. */
export const LINE_MAX = 512;
/** The chat view sawtooths between these sizes. */
export const VIEW_HIGH = 128_000;
export const VIEW_LOW = 64_000;
/** Compactions read a view merged further, so they share caches with each other. */
export const COMPACT_VIEW_HIGH = 32_000;
export const COMPACT_VIEW_LOW = 16_000;
/** View lines per cache block. */
export const BLOCK_LINES = 4;
/** Concurrent compaction calls. */
export const COMPACT_CONCURRENCY = 8;
/** Tool output is clipped to head + tail of this many chars. */
export const TOOL_CLIP = 30_000;
/** Longer texts are split across consecutive messages of this many chars. */
export const MESSAGE_CHUNK = 30_000;

export const TURN_MODEL = process.env.PITH_MODEL ?? "claude-opus-5-5";
export const TURN_EFFORT = (process.env.PITH_EFFORT ?? "high") as
  | "low" | "medium" | "high" | "xhigh" | "max";
export const COMPACT_MODEL = process.env.PITH_COMPACT_MODEL ?? "claude-haiku-5-5";
export const WORKSPACE = process.env.PITH_WORKSPACE ?? os.homedir();
