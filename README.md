# Strata

A native macOS chat app with lifelong memory: one endless conversation, logged verbatim and compressed into layers — dense near the present, sparse in the past.

Based on the memory architecture described in [this gist](https://gist.github.com/VictorTaelin/91837951a5ce5b38f341ec1ba1df6449).

## Layout (planned)

- `core/` — TypeScript (Bun) daemon: log, tree, view, compactor, turn runner, Claude Code subagents
- `app/` — SwiftUI macOS app
- `protocol/` — shared event types between app and core
