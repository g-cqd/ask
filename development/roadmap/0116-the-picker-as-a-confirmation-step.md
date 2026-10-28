---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0116 — The picker as a confirmation step

Owner wish (2026-10-28 20:33): extend the selector/picker into a confirmation tool for actions that benefit from the person's consent
before ask continues.

## Still owed

- List the actions that should ask: destructive commands, leaving the sandbox, overwriting configuration, deleting sessions, MCP tools
  marked destructive (ADR-0111 asks today in its own way).
- One shape for all of them: the question, the choices (allow once, always, refuse), the default, and the keys.
- Shared with 0117 (questions from the model), which needs the same picker with more choices.
