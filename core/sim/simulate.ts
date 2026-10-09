// Simulates a long chat with no API calls: view size, line count, batches
// and how much of each turn's prompt would be read from cache.
// Usage: node sim/simulate.ts [messages=30000]
import { BLOCK_LINES, VIEW_HIGH, VIEW_LOW } from "../src/config.ts";
import { View } from "../src/view.ts";

const N = Number(process.argv[2] ?? 30_000);
const LINE = 513;
const SYSTEM = 12_000; // tools + system prompt, in bytes
const v = new View({ sizeOf: () => LINE - 1, built: () => true }, VIEW_HIGH, VIEW_LOW);

let prev: string[] = [];
let prevMarks = new Set<number>(); // block counts at which the last request wrote cache entries
let read = 0;
let total = 0;
let batches = 0;
let sizeSum = 0;
let maxLines = 0;

for (let i = 0; i < N; i++) {
  if (v.push(i)) batches++;
  // A turn every other message (user + reply).
  if (i % 2) continue;
  const lines = v.lines.map(([l, k]) => `${l}:${k}`);
  const blocks: string[] = [];
  for (let k = 0; k < lines.length; k += BLOCK_LINES) blocks.push(lines.slice(k, k + BLOCK_LINES).join("|"));
  let same = 0;
  while (same < blocks.length && same < prev.length && blocks[same] === prev[same]) same++;
  // Longest earlier cache entry fully inside the shared prefix.
  let hit = 0;
  for (const m of prevMarks) if (m <= same && m > hit) hit = m;
  const hitBytes = SYSTEM + v.lines.slice(0, hit * BLOCK_LINES).length * LINE;
  read += hitBytes;
  total += SYSTEM + v.bytes;
  sizeSum += v.bytes;
  maxLines = Math.max(maxLines, v.lines.length);
  prev = blocks;
  prevMarks = new Set([Math.floor(lines.length / BLOCK_LINES), blocks.length]);
}

const turns = Math.ceil(N / 2);
console.log(`messages        ${N}`);
console.log(`batches         ${batches}`);
console.log(`avg view        ${(sizeSum / turns / 1000).toFixed(1)} KB`);
console.log(`max lines       ${maxLines}`);
console.log(`oldest line     level ${v.lines[0][0]} (${2 ** v.lines[0][0]} messages)`);
console.log(`cache read      ${((100 * read) / total).toFixed(1)}% of turn prefixes`);
