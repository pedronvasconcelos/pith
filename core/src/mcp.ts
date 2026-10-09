// Pith's memory as a stdio MCP server, for Codex turns and for other agents
// (Claude Code, Cursor, Codex) that want to consult the user's memory.
// Read-only: it never takes the chat lock and never writes.
import fs from "node:fs";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readAgentLog } from "./agents.ts";
import { DATA_DIR } from "./config.ts";
import { LogStore, type Message } from "./log.ts";
import { parseName, TreeStore } from "./tree.ts";
import type { Ref } from "./view.ts";
import { zoomText } from "./zoom.ts";

const text = (t: string) => ({ content: [{ type: "text" as const, text: t }] });
// Reload on every call: the log and tree only grow, and the app may be writing.
const messages = (): Message[] => new LogStore(DATA_DIR, true).messages;

const server = new McpServer(
  { name: "pith", version: "0.2.0" },
  {
    instructions:
      "Pith is the user's lifelong personal chat memory: one endless conversation between the user and their assistant, logged verbatim and condensed into lines. Use it to recall the user's preferences, decisions, facts about them and past work. Start with search (keywords) or overview (the whole chat, condensed), then zoom into a line until you have the detail whole. Lines are named id+n: the first message they cover and how many.",
  },
);

server.registerTool(
  "overview",
  {
    description:
      "The whole chat, condensed into lines, oldest first. Old lines cover many messages; recent lines cover few. Use zoom to open any line.",
    inputSchema: {},
  },
  async () => {
    const file = path.join(DATA_DIR, "compact-view.json");
    if (!fs.existsSync(file)) return text("The chat is empty.");
    const tree = new TreeStore(DATA_DIR);
    const lines = (JSON.parse(fs.readFileSync(file, "utf8")) as Ref[])
      .map(([l, i]) => tree.line(l, i))
      .filter((s): s is string => s !== undefined);
    return text(lines.length ? `<chat>\n${lines.join("\n")}\n</chat>` : "The chat is empty.");
  },
);

const fold = (s: string) => s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();

server.registerTool(
  "search",
  {
    description:
      "Find messages by keywords (any language, accents ignored). Returns the best matches, newest first among equals, with a snippet. Open one whole with zoom(id, 1).",
    inputSchema: { query: z.string(), limit: z.number().int().min(1).max(50).optional() },
  },
  async ({ query, limit }) => {
    const terms = fold(query).split(/\s+/).filter((t) => t.length > 1);
    if (!terms.length) return text("Give at least one keyword.");
    const hits: { m: Message; score: number; at: number }[] = [];
    for (const m of messages()) {
      const body = fold(m.text);
      let score = 0;
      let at = -1;
      for (const t of terms) {
        const k = body.indexOf(t);
        if (k < 0) continue;
        score += 1 + Math.min(body.split(t).length - 2, 3) * 0.2;
        if (at < 0) at = k;
      }
      if (score > 0) hits.push({ m, score: score + (m.kind === "user" ? 0.5 : 0), at });
    }
    hits.sort((a, b) => b.score - a.score || b.m.i - a.m.i);
    const out = hits.slice(0, limit ?? 12).map(({ m, at }) => {
      const start = Math.max(0, at - 80);
      const snippet = m.text.slice(start, start + 260).replace(/\s+/g, " ").trim();
      return `[${m.i}] ${m.kind} · ${m.date.slice(0, 10)}: ${start > 0 ? "…" : ""}${snippet}${start + 260 < m.text.length ? "…" : ""}`;
    });
    return text(out.length ? out.join("\n") : "No matches.");
  },
);

server.registerTool(
  "zoom",
  {
    description:
      "Open a chat line. zoom(id, n) on a line named id+n returns its two halves as lines; zoom(id, 1) returns the whole message id.",
    inputSchema: { id: z.number().int(), n: z.number().int() },
  },
  async ({ id, n }) => {
    const ref = parseName(id, n);
    if (!ref) return text("Not a line: n must be a power of two and id a multiple of n.");
    return text(zoomText(messages(), new TreeStore(DATA_DIR), ref[0], ref[1]));
  },
);

server.registerTool(
  "date",
  { description: "Return when message id was logged, in the user's local time.", inputSchema: { id: z.number().int() } },
  async ({ id }) => {
    const m = messages()[id];
    return text(m ? new Date(m.date).toString() : "No such message.");
  },
);

server.registerTool(
  "work_log",
  {
    description: "Open the full log of a helper run, by the [Name] its work message starts with.",
    inputSchema: { name: z.string() },
  },
  async ({ name }) => text(readAgentLog(path.join(DATA_DIR, "agents"), name) ?? "No such helper log."),
);

await server.connect(new StdioServerTransport());
