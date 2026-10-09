# Pith

A native macOS chat app with lifelong memory: one endless conversation, logged verbatim and condensed to its pith — the past packed dense at the center, the present growing at the edge.

Based on the memory architecture described in [this gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449).

## Layout (planned)

- `core/` — TypeScript (Bun) daemon: log, tree, view, compactor, turn runner, Claude Code subagents
- `app/` — SwiftUI macOS app
- `protocol/` — shared event types between app and core
