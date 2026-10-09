import type { Message } from "./log.ts";
import { first, nodeName, type TreeStore } from "./tree.ts";

/** zoom(id, n): the whole message for n = 1, else the two halves as lines. */
export function zoomText(messages: Message[], tree: TreeStore, l: number, i: number): string {
  if (first(l, i) >= messages.length) return "No such line.";
  if (l === 0) {
    const m = messages[i];
    return `[${m.i}] ${m.kind}:\n${m.text}`;
  }
  return [2 * i, 2 * i + 1]
    .filter((h) => first(l - 1, h) < messages.length)
    .map((h) => tree.line(l - 1, h) ?? `${nodeName(l - 1, h)} (not condensed yet; zoom further)`)
    .join("\n");
}
