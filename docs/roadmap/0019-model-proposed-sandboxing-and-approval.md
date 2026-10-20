---
status: in-progress
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

## Delivered — per-call narrowing (2026-10-20, ADR-0054, diary 49)

`bash`, `read`, `write` and `edit` take an optional `sandbox` argument that narrows that call; asking for more than the
run allows is refused, naming it. 0013 (the interactive screen) has landed, so the approval prompt is no longer blocked.

## Still owed

- **The approval prompt**: a widening request in the screen asks the user, naming exactly what would be allowed, once or
  for the session. Under `-p` it stays refused; the flags of ADR-0043 are the way to widen there.
- **Session-wide narrowing by the model** ("sandbox everything from now on"); undoing it is a widening.
