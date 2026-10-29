---
status: not-started
blocked-by: ["0150"]
date: 2026-10-29
---

# 0149 — Convert sessions between ask and other agents, both ways

Owner wish (2026-10-29 17:55): "Create a session converter to convert any session from a provider to an ask session, and any ask session
to any other providers session."

## Owed

- **Inventory first:** where each agent keeps sessions and in what shape (Claude Code's per-project JSONL, Codex's session files, Gemini
  CLI, and others the owner uses), with a real sample of each, read without changing it.
- **Import before export:** an ask session from another agent's file opens with `--resume` and continues on any provider. Export writes
  the other agent's format, checked by that agent opening it.
- **What cannot cross, said plainly:** signed or encrypted reasoning (Anthropic thinking signatures, OpenAI encrypted reasoning) is bound
  to its provider and is dropped or kept as plain text; provider-side IDs (cached prompts, response IDs) do not carry over; tool calls go
  through 0150's mapping, and a tool the target does not have becomes text.
- Tests from real samples (anonymised fixtures), red first, and a round trip (import, export, import) that loses only what the list above
  says it loses.
