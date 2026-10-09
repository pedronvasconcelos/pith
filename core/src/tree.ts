import fs from "node:fs";
import path from "node:path";
import { appendLine, bytes, day, flatten, readJsonl } from "./util.ts";

/** node(0,i) is message i condensed; node(l,i) merges node(l-1,2i) and node(l-1,2i+1). */
export interface TreeNode {
  l: number;
  i: number;
  text: string;
  size: number;
}

export const key = (l: number, i: number): string => `${l}:${i}`;
export const first = (l: number, i: number): number => i * 2 ** l;
export const span = (l: number): number => 2 ** l;
/** Nodes are named id+n: the first message they cover and how many. */
export const nodeName = (l: number, i: number): string => `${first(l, i)}+${span(l)}`;

/** Parses an id+n name back into [l, i]; null if it is not a valid node. */
export function parseName(id: number, n: number): [number, number] | null {
  if (!Number.isInteger(id) || !Number.isInteger(n) || id < 0 || n < 1) return null;
  const l = Math.log2(n);
  if (!Number.isInteger(l) || id % n !== 0) return null;
  return [l, id / n];
}

/** tree/YYYY-MM-DD.jsonl: every node, built once, never rebuilt. */
export class TreeStore {
  private nodes = new Map<string, TreeNode>();
  private dir: string;
  /** Highest level with any node, for stats. */
  depth = 0;

  constructor(dataDir: string) {
    this.dir = path.join(dataDir, "tree");
    fs.mkdirSync(this.dir, { recursive: true });
    for (const f of fs.readdirSync(this.dir).filter((f) => f.endsWith(".jsonl")).sort()) {
      for (const n of readJsonl<TreeNode>(path.join(this.dir, f))) this.remember(n);
    }
  }

  private remember(n: TreeNode): void {
    this.nodes.set(key(n.l, n.i), n);
    if (n.l > this.depth) this.depth = n.l;
  }

  get size(): number {
    return this.nodes.size;
  }

  has(l: number, i: number): boolean {
    return this.nodes.has(key(l, i));
  }

  get(l: number, i: number): TreeNode | undefined {
    return this.nodes.get(key(l, i));
  }

  put(l: number, i: number, text: string): TreeNode {
    const existing = this.get(l, i);
    if (existing) return existing;
    const n: TreeNode = { l, i, text, size: bytes(text) };
    appendLine(path.join(this.dir, `${day(new Date())}.jsonl`), n);
    this.remember(n);
    return n;
  }

  /** One view line: "id+n text", newlines flattened, no dates. */
  line(l: number, i: number): string | undefined {
    const n = this.get(l, i);
    return n && `${nodeName(l, i)} ${flatten(n.text)}`;
  }
}
