// Pith's memory tools as a stdio MCP server, for Codex turns.
// Read-only: it never takes the chat lock and never writes.
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readAgentLog } from "./agents.ts";
import { DATA_DIR } from "./config.ts";
import { LogStore } from "./log.ts";
import { parseName, TreeStore } from "./tree.ts";
import { zoomText } from "./zoom.ts";

const text = (t: string) => ({ content: [{ type: "text" as const, text: t }] });
const server = new McpServer({ name: "pith", version: "0.1.0" });

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
    // Reload every call: the log and tree only grow.
    return text(zoomText(new LogStore(DATA_DIR, true).messages, new TreeStore(DATA_DIR), ref[0], ref[1]));
  },
);

server.registerTool(
  "date",
  { description: "Return when message id was logged, in the user's local time.", inputSchema: { id: z.number().int() } },
  async ({ id }) => {
    const m = new LogStore(DATA_DIR, true).messages[id];
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
