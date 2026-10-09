import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";

process.env.PITH_FAKE = "1";
const { Memory } = await import("../src/memory.ts");

const until = async (cond: () => boolean) => {
  for (let k = 0; k < 500 && !cond(); k++) await new Promise((r) => setTimeout(r, 5));
  assert.ok(cond());
};

test("short messages become verbatim leaves; pairs merge into parents", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pith-"));
  const m = new Memory(dir);
  m.append("user", "oi");
  m.append("pith", "olá!");
  await until(() => m.tree.has(1, 0));
  assert.equal(m.tree.get(0, 0)!.text, "user: oi");
  assert.equal(m.tree.get(1, 0)!.text, "user: oi\npith: olá!");
  await m.ready();
  const { blocks } = m.blocks(m.view);
  assert.match(blocks[0].text, /^<chat>\n0\+1 user: oi\n1\+1 pith: olá!$/);
});

test("long messages are condensed to at most 512 bytes", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pith-"));
  const m = new Memory(dir);
  m.append("echo", "x".repeat(5000));
  await m.ready();
  assert.ok(m.tree.get(0, 0)!.size <= 512);
});

test("log, tree and view survive a restart", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pith-"));
  const a = new Memory(dir);
  for (let k = 0; k < 40; k++) a.append(k % 2 ? "pith" : "user", `mensagem ${k} `.repeat(30));
  await until(() => a.pending === 0);
  const lines = JSON.stringify(a.view.lines);
  fs.unlinkSync(path.join(dir, "lock"));
  const b = new Memory(dir);
  assert.equal(b.log.count, 40);
  assert.equal(JSON.stringify(b.view.lines), lines);
  assert.equal(b.tree.size, a.tree.size);
});

test("zoom opens a line into halves and a leaf into its message", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pith-"));
  const m = new Memory(dir);
  for (let k = 0; k < 4; k++) m.append("user", `m${k}`);
  await until(() => m.tree.has(2, 0));
  assert.equal(m.zoom(2, 0), "0+2 user: m0 user: m1\n2+2 user: m2 user: m3");
  assert.equal(m.zoom(0, 3), "[3] user:\nm3");
});
