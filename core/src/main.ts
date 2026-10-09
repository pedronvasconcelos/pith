import crypto from "node:crypto";
import fs from "node:fs";
import { Agents } from "./agents.ts";
import { DATA_DIR, FAKE, TURN_MODEL } from "./config.ts";
import { Memory } from "./memory.ts";
import { serve } from "./server.ts";
import { TurnRunner } from "./turn.ts";

fs.mkdirSync(DATA_DIR, { recursive: true });

const memory = new Memory(DATA_DIR);
const agents = new Agents(DATA_DIR);
const runner = new TurnRunner(memory, agents);

const token = process.env.PITH_TOKEN ?? crypto.randomBytes(24).toString("hex");
const port = Number(process.env.PITH_PORT ?? 0);

const server = serve({
  port,
  token,
  memory,
  agents,
  runner,
  onListening: (p) => {
    // The app reads this line to find the core.
    process.stdout.write(`PITH_READY ${JSON.stringify({ port: p, token: process.env.PITH_TOKEN ? undefined : token })}\n`);
    console.error(
      `[pith] ${memory.log.count} messages, ${memory.tree.size} nodes · ${FAKE ? "offline" : TURN_MODEL} · ws://127.0.0.1:${p}`,
    );
  },
});

const shutdown = () => {
  runner.cancel();
  server.close();
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
// When the app goes away, so does the core.
process.stdin.on("end", shutdown);
process.stdin.resume();
