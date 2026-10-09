# Pith

A native macOS chat app with lifelong memory: one endless conversation, logged verbatim and condensed to its pith — the past packed dense at the center, the present growing at the edge.

Based on the memory architecture described in [this gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449).

## How it works

- **Log** — every message is appended verbatim to `main/YYYY-MM-DD.jsonl` and never edited.
- **Tree** — Claude Haiku 5.5 condenses each message into a line of at most 512 bytes, and merges sibling lines into parents, once each.
- **View** — the lines covering the whole chat, oldest first. Past 128 KB, one batch merges the most due pairs back to 64 KB, so each turn reads ~97% of its prompt from cache.
- **Turns** — Claude Opus 5.5 gets `[tools][system][view][new message]` in a fresh call. It can `zoom` into any line, down to the whole message.
- **Hands** — real work on the Mac is delegated to Claude Code (Agent SDK). You approve its actions in the app.

## Layout

- `core/` — TypeScript core (Node 24): log, tree, view, compactor, turns, Claude Code helpers, local WebSocket API
- `app/` — SwiftUI app for macOS 26 (Liquid Glass): chat, live reasoning, the Strata memory inspector
- `scripts/` — app bundling and icon rendering

## Run

Requires macOS 26, Xcode 26 and Node.js 24+.

```bash
scripts/build-app.sh --open
```

Add your Anthropic API key in **Pith → Settings** (stored in the Keychain). Without a key the app runs offline, which is handy for trying the UI.

Data lives in `~/Library/Application Support/Pith`.

## Develop

```bash
cd core && npm install && npm test   # unit tests
cd core && npm run sim               # 30k-message memory simulation, no API calls
cd app && swift run                  # app against core/ in this checkout
```

Dev-only environment variables: `PITH_DATA` (data folder), `PITH_VIEW_HIGH` / `PITH_VIEW_LOW` (view sizes), `PITH_SNAPSHOT` (write window captures to a PNG), `PITH_DEV_TOKEN` (fixed core token).
