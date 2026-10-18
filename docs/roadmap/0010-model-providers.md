---
status: not-started
blocked-by: ["0009"]
date: 2026-10-18
---

# 0010 — Model providers

**One provider end to end, before a second is designed.** A second provider is what reveals the
abstraction; designing for it up front produces the widest possible interface and the least useful one.

## The choice is open

`pi-integrations` already has working, tested providers for Claude, Codex, Antigravity, Spettro, Mistral
Vibe and on-device Apple Foundation Models. Reusing their auth and transport knowledge is cheaper than
rediscovering OAuth edge cases — and the streaming and tool-call decoding each one needs is where the real
work is.

The first provider should be decided before `0011`, because tool-call decoding differs per provider and
`0011` must not be built against a guess. **This is the open question recorded in the plan.**

## What lands

- Streaming, incrementally decoded from bytes rather than reassembled per chunk.
- Tool-call decoding, including partial calls split across chunk boundaries.
- Usage accounting — pi records a `UsageEntry` per response, and compaction depends on it.
- Errors as a typed path, not a thrown string: an overloaded provider and a malformed response are
  different problems.

## Hot-path note

Decoding a byte once instead of re-scanning it is a named runtime principle in the white paper. A stream
that re-scans its buffer per chunk is the most likely way this entry goes wrong, and the input-delay
budget is what catches it.

## Done when

One provider streams a full turn including tool calls, usage is recorded, and a mid-stream failure
recovers or reports cleanly.