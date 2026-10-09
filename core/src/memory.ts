import { EventEmitter } from "node:events";
import path from "node:path";
import type Anthropic from "@anthropic-ai/sdk";
import {
  BLOCK_LINES,
  COMPACT_CONCURRENCY,
  COMPACT_VIEW_HIGH,
  COMPACT_VIEW_LOW,
  LINE_MAX,
  MESSAGE_CHUNK,
  TOOL_CLIP,
  VIEW_HIGH,
  VIEW_LOW,
} from "./config.ts";
import { type Kind, LogStore, type Message } from "./log.ts";
import { compact } from "./model.ts";
import { compressTask, mergeTask } from "./prompt.ts";
import { Stats } from "./stats.ts";
import { TreeStore, first, key, nodeName, span } from "./tree.ts";
import { bytes, chunk, clip, Signal } from "./util.ts";
import { type Ref, View } from "./view.ts";

type Job = { l: number; i: number };

export interface MemoryEvents {
  message: [Message];
  node: [l: number, i: number];
  changed: [];
}

/**
 * Log + tree + views + compactor. Every message becomes a leaf; every pair of
 * built siblings becomes their parent. Nodes are built once and never rebuilt.
 */
export class Memory extends EventEmitter<MemoryEvents> {
  readonly log: LogStore;
  readonly tree: TreeStore;
  readonly view: View;
  /** The view merged further, read by compactions so they share caches. */
  readonly compactView: View;
  readonly stats = new Stats();

  private leaves: number[] = [];
  private merges: Job[] = [];
  private running = new Set<string>();
  private built = new Signal();
  /** Last compaction error, so a waiting turn can fail instead of hanging. */
  failure: string | null = null;

  constructor(dataDir: string) {
    super();
    this.log = new LogStore(dataDir);
    this.tree = new TreeStore(dataDir);
    const deps = {
      sizeOf: (l: number, i: number) => {
        const n = this.tree.get(l, i);
        return n ? bytes(nodeName(l, i)) + 1 + n.size : bytes(nodeName(l, i)) + 1 + this.estimate(l, i);
      },
      built: (l: number, i: number) => this.tree.has(l, i),
    };
    this.view = new View(deps, VIEW_HIGH, VIEW_LOW, path.join(dataDir, "view.json"));
    this.compactView = new View(deps, COMPACT_VIEW_HIGH, COMPACT_VIEW_LOW, path.join(dataDir, "compact-view.json"));
    // Catch views up with messages logged before a crash.
    for (const v of [this.view, this.compactView]) {
      for (let i = v.covered; i < this.log.count; i++) v.push(i);
    }
    this.recover();
  }

  private estimate(l: number, i: number): number {
    if (l > 0) return LINE_MAX;
    const m = this.log.messages[i];
    return m ? Math.min(LINE_MAX, bytes(`${m.kind}: ${m.text}`)) : LINE_MAX;
  }

  /** One startup scan for unbuilt work; after this, work arrives through queues. */
  private recover(): void {
    for (let i = 0; i < this.log.count; i++) if (!this.tree.has(0, i)) this.leaves.push(i);
    for (let l = 0; ; l++) {
      const count = Math.floor(this.log.count / span(l));
      if (count < 2) break;
      for (let i = 0; i + 1 < count; i += 2) {
        if (this.tree.has(l, i) && this.tree.has(l, i + 1) && !this.tree.has(l + 1, i / 2)) {
          this.merges.push({ l: l + 1, i: i / 2 });
        }
      }
    }
    this.pump();
  }

  /** Logs text as one or more messages; long tool output is clipped, other long text split. */
  append(kind: Kind, text: string): Message[] {
    const parts = kind === "echo" ? [clip(text, TOOL_CLIP)] : chunk(text, MESSAGE_CHUNK);
    const out: Message[] = [];
    for (const part of parts) {
      const m = this.log.append(kind, part);
      this.leaves.push(m.i);
      this.view.push(m.i);
      this.compactView.push(m.i);
      out.push(m);
      this.emit("message", m);
    }
    this.pump();
    this.emit("changed");
    return out;
  }

  get pending(): number {
    return this.leaves.length + this.merges.length + this.running.size;
  }

  /** Resolves once every line of the chat view is built. */
  async ready(): Promise<void> {
    while (this.view.lines.some(([l, i]) => !this.tree.has(l, i))) {
      if (this.failure) throw new Error(`Não consegui condensar a memória: ${this.failure}`);
      await this.built.wait();
    }
  }

  /** The view as prompt blocks: "<chat>", lines in blocks of 4, "</chat>". */
  blocks(view: View, skipUnbuilt = false): { blocks: Anthropic.TextBlockParam[]; complete: number } {
    const lines: string[] = [];
    for (const [l, i] of view.lines) {
      const line = this.tree.line(l, i);
      if (line !== undefined) lines.push(line);
      else if (!skipUnbuilt) throw new Error(`view line ${nodeName(l, i)} is not built`);
    }
    const blocks: Anthropic.TextBlockParam[] = [];
    for (let k = 0; k < lines.length; k += BLOCK_LINES) {
      const group = lines.slice(k, k + BLOCK_LINES).join("\n");
      blocks.push({ type: "text", text: k === 0 ? `<chat>\n${group}` : group });
    }
    if (blocks.length === 0) blocks.push({ type: "text", text: "<chat>" });
    const complete = Math.floor(lines.length / BLOCK_LINES);
    return { blocks, complete };
  }

  /** Puts cache marks on the last complete 4-line block and on the view's end. */
  static mark(blocks: Anthropic.TextBlockParam[], complete: number): Anthropic.TextBlockParam[] {
    const out = blocks.map((b) => ({ ...b }));
    const ends = new Set([complete - 1, out.length - 1].filter((k) => k >= 0));
    for (const k of ends) out[k].cache_control = { type: "ephemeral" };
    return out;
  }

  private context(): Anthropic.TextBlockParam[] {
    const { blocks, complete } = this.blocks(this.compactView, true);
    return [...Memory.mark(blocks, complete), { type: "text", text: "</chat>" }];
  }

  /** Starts ready work, up to the concurrency limit. A leaf waits until fewer than 8 earlier leaves are unbuilt. */
  private pump(): void {
    while (this.running.size < COMPACT_CONCURRENCY) {
      const merge = this.merges.shift();
      if (merge) {
        this.start(merge);
        continue;
      }
      const leaf = this.leaves[0];
      if (leaf === undefined) break;
      const earlier = [...this.running].filter((k) => k.startsWith("0:") && Number(k.slice(2)) < leaf).length;
      if (earlier >= COMPACT_CONCURRENCY) break;
      this.leaves.shift();
      this.start({ l: 0, i: leaf });
    }
  }

  private start(job: Job): void {
    const k = key(job.l, job.i);
    if (this.tree.has(job.l, job.i) || this.running.has(k)) return;
    this.running.add(k);
    this.build(job)
      .catch((err) => {
        console.error(`[compactor] ${nodeName(job.l, job.i)} failed:`, err?.message ?? err);
        this.failure = err?.message ?? String(err);
        this.built.fire();
        // Retry later, without blocking the rest.
        setTimeout(() => {
          if (job.l === 0) this.leaves.push(job.i);
          else this.merges.push(job);
          this.pump();
        }, 5000);
      })
      .finally(() => {
        this.running.delete(k);
        this.pump();
        this.emit("changed");
      });
  }

  private async build({ l, i }: Job): Promise<void> {
    let text: string;
    if (l === 0) {
      const m = this.log.messages[i];
      const verbatim = `${m.kind}: ${m.text}`;
      text = bytes(verbatim) <= LINE_MAX ? verbatim : await compact(this.context(), compressTask(i, m.kind, m.text), this.stats);
    } else {
      const a = this.tree.get(l - 1, 2 * i)!;
      const b = this.tree.get(l - 1, 2 * i + 1)!;
      const joined = `${a.text}\n${b.text}`;
      text =
        bytes(joined) <= LINE_MAX
          ? joined
          : await compact(
              this.context(),
              mergeTask(nodeName(l - 1, 2 * i), a.text, nodeName(l - 1, 2 * i + 1), b.text),
              this.stats,
            );
    }
    this.tree.put(l, i, text);
    this.failure = null;
    this.view.refresh();
    this.compactView.refresh();
    this.emit("node", l, i);
    this.built.fire();
    // The parent is ready once both siblings exist.
    const sib = i ^ 1;
    if (this.tree.has(l, sib) && !this.tree.has(l + 1, i >> 1)) {
      this.merges.push({ l: l + 1, i: i >> 1 });
    }
  }

  /** zoom(id, n): the whole message for n = 1, else the two halves as lines. */
  zoom(l: number, i: number): string {
    if (first(l, i) >= this.log.count) return "No such line.";
    if (l === 0) {
      const m = this.log.messages[i];
      return `[${m.i}] ${m.kind}:\n${m.text}`;
    }
    const halves: Ref[] = [
      [l - 1, 2 * i],
      [l - 1, 2 * i + 1],
    ];
    return halves
      .map(([hl, hi]) => {
        if (first(hl, hi) >= this.log.count) return null;
        return this.tree.line(hl, hi) ?? `${nodeName(hl, hi)} (not condensed yet; zoom further)`;
      })
      .filter(Boolean)
      .join("\n");
  }
}
