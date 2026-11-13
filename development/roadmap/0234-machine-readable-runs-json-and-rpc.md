---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0234 — Machine-readable runs: `ask -p --json`, then an RPC mode

From the study of other agents (proposal 2), chosen 2026-11-13, a cheap one done first.

1. `ask -p --json`: the run's events as JSON lines on standard output (text, thinking, tool calls and results, usage, the end), one
   object each, with a version field; the final reply as today without it.
2. `ask serve`: JSON-RPC on stdio for a long-lived driver: send a prompt, stream its events, answer approvals and questions, cancel.
   ACP (the next entry) is built on it.

## Done when

A probe reads a `--json` run's lines and finds each event kind; the RPC mode drives two prompts and an approval.
