import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { first, nodeName, parseName, span } from "../src/tree.ts";
import { View } from "../src/view.ts";

/** A view over an always-built tree with 512-byte lines. */
function sim(total: number, high = 128_000, low = 64_000) {
  const v = new View({ sizeOf: () => 512, built: () => true }, high, low);
  const sizes: number[] = [];
  for (let i = 0; i < total; i++) {
    v.push(i);
    sizes.push(v.bytes);
  }
  return { v, sizes };
}

test("names round-trip", () => {
  assert.equal(nodeName(3, 5), "40+8");
  assert.deepEqual(parseName(40, 8), [3, 5]);
  assert.equal(parseName(41, 8), null);
  assert.equal(parseName(40, 6), null);
});

test("view always covers the whole chat, contiguously and in order", () => {
  const { v } = sim(5000);
  let next = 0;
  for (const [l, i] of v.lines) {
    assert.equal(first(l, i), next);
    next += span(l);
  }
  assert.equal(next, 5000);
});

test("view sawtooths between low and high", () => {
  const { sizes } = sim(20_000);
  const per = 513;
  for (const s of sizes) assert.ok(s <= 128_000 + per, `size ${s} above high`);
  const afterBatch = sizes.filter((s, k) => k > 0 && s < sizes[k - 1]);
  assert.ok(afterBatch.length > 10);
  for (const s of afterBatch) assert.ok(s <= 64_000, `batch left ${s}`);
});

test("old lines are coarse, recent lines are fine", () => {
  const { v } = sim(20_000);
  const levels = v.lines.map(([l]) => l);
  assert.equal(levels.at(-1), 0);
  // Levels never increase towards the present.
  for (let k = 1; k < levels.length; k++) assert.ok(levels[k] <= levels[k - 1] + 1);
  assert.ok(levels[0] >= 6, `oldest line is level ${levels[0]}`);
});

test("merges wait for parents to be built", () => {
  const v = new View({ sizeOf: () => 512, built: (l) => l <= 1 }, 4096, 2048);
  for (let i = 0; i < 100; i++) v.push(i);
  assert.ok(v.lines.every(([l]) => l <= 1));
});

test("view persists and reloads byte-identical", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pith-"));
  const file = path.join(dir, "view.json");
  const deps = { sizeOf: () => 512, built: () => true };
  const a = new View(deps, 8192, 4096, file);
  for (let i = 0; i < 300; i++) a.push(i);
  const b = new View(deps, 8192, 4096, file);
  assert.deepEqual(b.lines, a.lines);
  assert.equal(b.bytes, a.bytes);
});
