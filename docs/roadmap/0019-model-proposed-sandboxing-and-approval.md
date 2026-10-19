---
status: not-started
blocked-by:
date: 2026-10-19
decision: ADR-0020
---

# 0019 — The model proposes sandboxing; only the user widens it

ADR-0020's model-facing half.

## What lands

- **Every tool's schema gains an optional `sandbox` object** with the same capabilities. A narrowing
  request applies atomically to that call.
- **A widening request is never applied silently:**
  - interactively it becomes an approval prompt, naming exactly what would be allowed, once or for the
    session;
  - under `-p` it is refused unless flags already allow it.
- **The model can narrow the whole session** ("sandbox everything from now on"). Undoing it is a widening.
- **The system prompt states the active policy.** Denials tell the model which capability refused, and
  that changing policy is the user's decision.
- **`-p` flags:** `--sandbox read-only|workspace-write|off`, `--allow-network`, `--allow-write <path>`,
  `--deny-read <path>`.

## Blocked by

`0013`, for the approval prompt: an interactive question needs the interactive screen.
