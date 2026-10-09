import fs from "node:fs";

export const bytes = (s: string): number => Buffer.byteLength(s, "utf8");

/** Cuts a string to at most `max` UTF-8 bytes without splitting a character. */
export function cutBytes(s: string, max: number): string {
  const buf = Buffer.from(s, "utf8");
  if (buf.length <= max) return s;
  let end = max;
  while (end > 0 && (buf[end] & 0xc0) === 0x80) end--;
  return buf.subarray(0, end).toString("utf8");
}

export const flatten = (s: string): string => s.replace(/\s*\n\s*/g, " ").trim();

/** Keeps the head and tail of a long text. */
export function clip(s: string, max: number): string {
  if (s.length <= max) return s;
  const half = Math.floor(max / 2);
  return `${s.slice(0, half)}\n… [${s.length - max} chars clipped] …\n${s.slice(-half)}`;
}

export function chunk(s: string, size: number): string[] {
  if (s.length <= size) return [s];
  const out: string[] = [];
  for (let k = 0; k < s.length; k += size) out.push(s.slice(k, k + size));
  return out;
}

export const day = (d: Date): string => d.toISOString().slice(0, 10);

/** Appends one line and flushes it to disk before returning. */
export function appendLine(file: string, obj: unknown): void {
  const fd = fs.openSync(file, "a");
  try {
    fs.writeSync(fd, JSON.stringify(obj) + "\n");
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

export function readJsonl<T>(file: string): T[] {
  if (!fs.existsSync(file)) return [];
  const out: T[] = [];
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line) as T);
    } catch {
      // A torn last line from a crash: ignore it.
    }
  }
  return out;
}

export function writeAtomic(file: string, data: string): void {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, data);
  fs.renameSync(tmp, file);
}

export class Signal {
  private waiters: Array<() => void> = [];
  wait(): Promise<void> {
    return new Promise((r) => this.waiters.push(r));
  }
  fire(): void {
    const w = this.waiters;
    this.waiters = [];
    for (const r of w) r();
  }
}
