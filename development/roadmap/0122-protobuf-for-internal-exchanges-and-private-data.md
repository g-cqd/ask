---
status: not-started
blocked-by: [AemiProtobuf roadmap]
date: 2026-10-28
---

# 0122 — Protobuf for internal exchanges and data people do not edit

Owner wish (2026-10-28 22:40): investigate Protobuf, through AemiProtobuf, to speed up communication between ask's tools and between
ask-related tools, and to persist data that an average user is not meant to edit. It requires AemiProtobuf's own roadmap to be finished
first.

## Still owed

- Wait for AemiProtobuf's roadmap to be complete (the owner's condition).
- Candidates: state and caches under ask's state directory (model lists, learned windows), messages between ask processes (0115's session
  registry), MCP has to stay JSON-RPC by its protocol. Session files stay JSONL: people read and resume them.
- Compare size and speed with AemiJSON on the real payloads before moving anything.
