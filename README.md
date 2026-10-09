# Pith

A native macOS chat app with lifelong memory: one endless conversation, logged verbatim and condensed to its pith — the past packed dense at the center, the present growing at the edge.

Based on the memory architecture described in [this gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449).

<p align="center"><img src="assets/Pith.png" width="160" alt="Pith icon: tree rings around an amber center"></p>

## The name

In botany, the *pith* is the soft core at the very center of a tree's stem: the oldest part of the tree, with every later ring grown around it. In everyday English it also means the essence of something, as in "the pith of the matter".

Both meanings describe how Pith remembers. A tree's cross-section is a record of time: rings near the center are old and packed tight, rings near the bark are recent and wide. Pith's memory has the same shape. Old messages are condensed into dense lines that each cover many messages, while recent ones stay close to word-for-word. Each condensed line keeps the pith of what was said, and the whole conversation stays within reach, from the first message to the last.

The icon is that cross-section: rings in sapwood-to-heartwood tones, tight at the center and wide at the edge, around an amber pith. The **Strata** panel in the app shows the same idea as a geological column, with the newest layers on top.

## How it works

- **Log** — every message is appended verbatim to `main/YYYY-MM-DD.jsonl` and never edited.
- **Tree** — Claude Haiku 5.5 condenses each message into a line of at most 512 bytes, and merges sibling lines into parents, once each.
- **View** — the lines covering the whole chat, oldest first. Past 128 KB, one batch merges the most due pairs back to 64 KB, so each turn reads ~97% of its prompt from cache.
- **Turns** — the model gets `[tools][system][view][new message]` in a fresh call. It can `zoom` into any line, down to the whole message.
- **Hands** — real work on the Mac is delegated to Claude Code (Agent SDK, you approve each action) or Codex (works alone inside its sandbox).

## Providers

| | Conversation | Memory | Credentials |
|---|---|---|---|
| Claude | Opus 5.5 / Sonnet 5.5 | Haiku 5.5 | Anthropic API key |
| Gemini | 3.8 Flash / 3.1 Pro | 3.5 Flash-Lite | Gemini API key |
| ChatGPT | your Codex models | same | your own `codex login` |

ChatGPT runs through OpenAI's official Codex SDK and CLI on your login, so usage counts against your plan. Pith never reads or reuses Codex's tokens; Codex reaches Pith's memory tools through a local, read-only MCP server (`core/src/mcp.ts`).

## Use your memory from other agents

Pith's read-only MCP server lets Claude Code, Cursor and Codex consult your memory while you work: `search` by keywords, `overview` for the whole chat condensed, `zoom` into any line, `date` and `work_log`. Turn each one on in **Settings → Integrations**; Pith registers itself with each tool's own mechanism (`claude mcp add`, `~/.cursor/mcp.json`, `codex mcp add`). Nothing is ever written to Pith from there.

## The tree window

**Window → Árvore** (⇧⌘B) draws the memory as a small grove. Each leaf is a line Pith reads: fresh green leaves are recent messages kept whole, golden ones are old conversation condensed. Pairs of leaves join into branches and branches into a trunk, one tree per complete part of the chat: the big tree is the past, the saplings are today. Hover a leaf to read it; click to open it down to the original messages.

## Layout

- `core/` — TypeScript core (Node 24): log, tree, view, compactor, turns, Claude Code helpers, local WebSocket API
- `app/` — SwiftUI app for macOS 26 (Liquid Glass): chat, live reasoning, the Strata memory inspector
- `scripts/` — app bundling and icon rendering

## Run

Requires macOS 26, Xcode 26 and Node.js 24+.

```bash
scripts/build-app.sh --open
```

Pick a provider in **Pith → Settings**: an Anthropic or Gemini key (stored in the Keychain), or ChatGPT through Codex. Without one the app runs offline, which is handy for trying the UI.

Data lives in `~/Library/Application Support/Pith`.

## Develop

```bash
cd core && npm install && npm test   # unit tests
cd core && npm run sim               # 30k-message memory simulation, no API calls
cd app && swift run                  # app against core/ in this checkout
```

Dev-only environment variables: `PITH_DATA` (data folder), `PITH_VIEW_HIGH` / `PITH_VIEW_LOW` (view sizes), `PITH_SNAPSHOT` (write window captures to a PNG), `PITH_OPEN_SETTINGS` / `PITH_OPEN_BRANCHES` (open a window at launch), `PITH_SNAPSHOT_WINDOW` (which window to capture), `PITH_DEV_TOKEN` (fixed core token).
