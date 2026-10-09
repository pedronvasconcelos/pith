/** Per-MTok prices: input, cache write (5 min), cache read, output. */
const PRICES: Record<string, [number, number, number, number]> = {
  "claude-opus-5-5": [4, 5, 0.2, 20],
  "claude-sonnet-5-5": [2, 2.5, 0.2, 10],
  "claude-haiku-5-5": [0.1, 0.125, 0.01, 0.5],
};

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}

export interface CallStats {
  input: number;
  cacheWrite: number;
  cacheRead: number;
  output: number;
}

export class Stats {
  turns = { calls: 0, input: 0, cacheWrite: 0, cacheRead: 0, output: 0 };
  compactions = { calls: 0, input: 0, cacheWrite: 0, cacheRead: 0, output: 0 };
  costUSD = 0;
  last: CallStats | null = null;

  add(kind: "turns" | "compactions", model: string, u: Usage): CallStats {
    const c: CallStats = {
      input: u.input_tokens,
      cacheWrite: u.cache_creation_input_tokens ?? 0,
      cacheRead: u.cache_read_input_tokens ?? 0,
      output: u.output_tokens,
    };
    const t = this[kind];
    t.calls++;
    t.input += c.input;
    t.cacheWrite += c.cacheWrite;
    t.cacheRead += c.cacheRead;
    t.output += c.output;
    const p = PRICES[model] ?? PRICES["claude-opus-5-5"];
    this.costUSD += (c.input * p[0] + c.cacheWrite * p[1] + c.cacheRead * p[2] + c.output * p[3]) / 1e6;
    if (kind === "turns") this.last = c;
    return c;
  }

  /** Share of prompt tokens read from cache. */
  static hitRate(t: { input: number; cacheWrite: number; cacheRead: number }): number {
    const all = t.input + t.cacheWrite + t.cacheRead;
    return all ? t.cacheRead / all : 0;
  }
}
