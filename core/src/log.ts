import fs from "node:fs";
import path from "node:path";
import { appendLine, bytes, day, readJsonl } from "./util.ts";

export type Kind = "user" | "pith" | "tool" | "echo" | "work" | "note";

export interface Message {
  i: number;
  kind: Kind;
  text: string;
  size: number;
  date: string;
}

/** The append-only chat log: main/YYYY-MM-DD.jsonl. One process owns it. */
export class LogStore {
  readonly messages: Message[] = [];
  private dir: string;
  private lockFile: string;

  constructor(dataDir: string) {
    this.dir = path.join(dataDir, "main");
    fs.mkdirSync(this.dir, { recursive: true });
    this.lockFile = path.join(dataDir, "lock");
    this.lock();
    for (const f of fs.readdirSync(this.dir).filter((f) => f.endsWith(".jsonl")).sort()) {
      for (const m of readJsonl<Message>(path.join(this.dir, f))) {
        if (m.i === this.messages.length) this.messages.push(m);
      }
    }
  }

  private lock(): void {
    if (fs.existsSync(this.lockFile)) {
      const pid = Number(fs.readFileSync(this.lockFile, "utf8"));
      let alive = false;
      try {
        if (pid && pid !== process.pid) {
          process.kill(pid, 0);
          alive = true;
        }
      } catch {}
      if (alive) throw new Error(`chat is locked by process ${pid}`);
    }
    fs.writeFileSync(this.lockFile, String(process.pid));
    const release = () => {
      try {
        if (fs.readFileSync(this.lockFile, "utf8") === String(process.pid)) fs.unlinkSync(this.lockFile);
      } catch {}
    };
    process.on("exit", release);
  }

  get count(): number {
    return this.messages.length;
  }

  append(kind: Kind, text: string): Message {
    const now = new Date();
    const m: Message = { i: this.messages.length, kind, text, size: bytes(text), date: now.toISOString() };
    appendLine(path.join(this.dir, `${day(now)}.jsonl`), m);
    this.messages.push(m);
    return m;
  }
}
