import { ApiError, type Content, type FunctionDeclaration, GoogleGenAI, type Part, type ThinkingLevel } from "@google/genai";
import { GEMINI_COMPACT_MODEL, GEMINI_MODEL, TURN_EFFORT } from "../config.ts";
import { SYSTEM, TOOLS } from "../prompt.ts";
import type { Ask, TurnContext } from "./types.ts";

let client: GoogleGenAI | null = null;
const gemini = (): GoogleGenAI => (client ??= new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY }));

const declarations: FunctionDeclaration[] = TOOLS.map((t) => ({
  name: t.name,
  description: t.description,
  parametersJsonSchema: t.input_schema,
}));

const level = (): ThinkingLevel =>
  (TURN_EFFORT === "low" ? "LOW" : TURN_EFFORT === "medium" ? "MEDIUM" : "HIGH") as ThinkingLevel;

/**
 * Same prompt order as Claude: system, then the view, then the new message.
 * Gemini caches stable prefixes implicitly, so the view still reads from cache.
 */
export async function geminiTurn(ctx: TurnContext): Promise<void> {
  const contents: Content[] = [{ role: "user", parts: [{ text: `${ctx.viewText}\n\n${ctx.text}` }] }];
  for (;;) {
    if (ctx.signal.aborted) return;
    const stream = await gemini().models.generateContentStream({
      model: GEMINI_MODEL,
      contents,
      config: {
        systemInstruction: SYSTEM,
        tools: [{ functionDeclarations: declarations }],
        thinkingConfig: { includeThoughts: true, thinkingLevel: level() },
        abortSignal: ctx.signal,
      },
    });
    // Parts go back exactly as received: they carry thought signatures.
    const parts: Part[] = [];
    let current: "text" | "thinking" | null = null;
    let usage: { prompt: number; cached: number; output: number } | null = null;
    for await (const chunk of stream) {
      for (const p of chunk.candidates?.[0]?.content?.parts ?? []) {
        parts.push(p);
        if (p.text) {
          const kind = p.thought ? "thinking" : "text";
          if (kind !== current) ctx.block((current = kind));
          ctx.delta(kind, p.text);
        }
      }
      const u = chunk.usageMetadata;
      if (u) {
        usage = {
          prompt: u.promptTokenCount ?? 0,
          cached: u.cachedContentTokenCount ?? 0,
          output: (u.candidatesTokenCount ?? 0) + (u.thoughtsTokenCount ?? 0),
        };
      }
    }
    if (usage) {
      ctx.stats.add("turns", GEMINI_MODEL, {
        input: usage.prompt - usage.cached,
        cacheWrite: 0,
        cacheRead: usage.cached,
        output: usage.output,
      });
    }

    const text = parts
      .filter((p) => p.text && !p.thought)
      .map((p) => p.text)
      .join("")
      .trim();
    if (text) ctx.log("pith", text);

    const calls = parts.filter((p) => p.functionCall).map((p) => p.functionCall!);
    if (calls.length === 0) return;

    const results = await Promise.all(
      calls.map((c, k) => ctx.runTool(c.id ?? `gemini-${k}`, c.name ?? "", (c.args ?? {}) as Record<string, unknown>)),
    );
    const reply: Part[] = calls.map((c, k) => ({
      functionResponse: {
        id: c.id,
        name: c.name,
        response: results[k].error ? { error: results[k].text } : { output: results[k].text },
      },
    }));
    const late = ctx.takeLate();
    if (late.length) reply.push({ text: `[New message from the user, sent while you worked]\n${late.join("\n\n")}` });
    contents.push({ role: "model", parts });
    contents.push({ role: "user", parts: reply });
  }
}

export const geminiAsk: Ask = async (context, turns, stats) => {
  const contextText = context.map((b) => b.text).join("\n");
  const contents: Content[] = turns.map((t, k) => ({
    role: k % 2 ? "model" : "user",
    parts: [{ text: k === 0 ? `${contextText}\n\n${t}` : t }],
  }));
  const res = await gemini().models.generateContent({
    model: GEMINI_COMPACT_MODEL,
    contents,
    config: { systemInstruction: SYSTEM },
  });
  const u = res.usageMetadata;
  stats.add("compactions", GEMINI_COMPACT_MODEL, {
    input: (u?.promptTokenCount ?? 0) - (u?.cachedContentTokenCount ?? 0),
    cacheWrite: 0,
    cacheRead: u?.cachedContentTokenCount ?? 0,
    output: (u?.candidatesTokenCount ?? 0) + (u?.thoughtsTokenCount ?? 0),
  });
  return (res.text ?? "").trim();
};

export function describeGeminiError(err: unknown): string | null {
  if (!(err instanceof ApiError)) return null;
  if (err.status === 400 && /api key/i.test(err.message)) return "Chave do Gemini inválida. Confira nos Ajustes.";
  if (err.status === 401 || err.status === 403) return "A chave do Gemini não tem acesso a este modelo.";
  if (err.status === 429) return "Limite de uso do Gemini atingido. Tente de novo em instantes.";
  return `Erro da API do Gemini (${err.status}): ${err.message}`;
}
