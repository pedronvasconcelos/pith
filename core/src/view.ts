import fs from "node:fs";
import { first, span } from "./tree.ts";
import { writeAtomic } from "./util.ts";

export type Ref = [l: number, i: number];

export interface ViewDeps {
  /** Rendered byte size of a line (an estimate is fine while the node is unbuilt). */
  sizeOf(l: number, i: number): number;
  /** Whether node(l, i) exists in the tree. */
  built(l: number, i: number): boolean;
}

/**
 * The nodes covering the whole chat, oldest first. It grows by one line per
 * message and, past `high` bytes, one batch merges the most due sibling pairs
 * until it is back under `low`. Saved as-is and never rebuilt from the log,
 * so restarts keep the exact bytes the prompt cache saw.
 */
export class View {
  lines: Ref[] = [];
  bytes = 0;

  private deps: ViewDeps;
  private high: number;
  private low: number;
  private file?: string;

  constructor(deps: ViewDeps, high: number, low: number, file?: string) {
    this.deps = deps;
    this.high = high;
    this.low = low;
    this.file = file;
    if (file && fs.existsSync(file)) {
      this.lines = JSON.parse(fs.readFileSync(file, "utf8")) as Ref[];
      this.recount();
    }
  }

  /** Messages the view covers. */
  get covered(): number {
    const last = this.lines.at(-1);
    return last ? first(last[0], last[1]) + span(last[0]) : 0;
  }

  recount(): void {
    this.bytes = this.lines.reduce((s, [l, i]) => s + this.deps.sizeOf(l, i) + 1, 0);
  }

  /** Appends message i as a leaf line. Returns whether a batch merged lines. */
  push(i: number): boolean {
    this.lines.push([0, i]);
    this.bytes += this.deps.sizeOf(0, i) + 1;
    const merged = this.bytes > this.high && this.batch(i + 1) > 0;
    this.save();
    return merged;
  }

  /**
   * Called when a node is built: its estimated size becomes exact, and a
   * batch that was waiting on unbuilt parents can finish.
   */
  refresh(total: number): void {
    this.recount();
    if (this.bytes > this.high && this.batch(total) > 0) this.save();
  }

  /**
   * Merges the most due pairs until the view fits in `low`. A pair is due by
   * how long ago it ended, in units of its own line size: (T - last) / 2^l.
   * Only pairs whose parent node is already built can merge.
   */
  batch(total: number): number {
    let merges = 0;
    while (this.bytes > this.low) {
      let best = -1;
      let bestDue = -Infinity;
      for (let j = 0; j + 1 < this.lines.length; j++) {
        const [la, ia] = this.lines[j];
        const [lb, ib] = this.lines[j + 1];
        if (la !== lb || ia % 2 !== 0 || ib !== ia + 1) continue;
        if (!this.deps.built(la + 1, ia / 2)) continue;
        const last = first(lb, ib) + span(lb) - 1;
        const due = (total - last) / span(la);
        if (due > bestDue) {
          bestDue = due;
          best = j;
        }
      }
      if (best < 0) break;
      const [l, i] = this.lines[best];
      const before = this.deps.sizeOf(l, i) + this.deps.sizeOf(l, i + 1) + 2;
      this.lines.splice(best, 2, [l + 1, i / 2]);
      this.bytes += this.deps.sizeOf(l + 1, i / 2) + 1 - before;
      merges++;
    }
    return merges;
  }

  save(): void {
    if (this.file) writeAtomic(this.file, JSON.stringify(this.lines));
  }
}
