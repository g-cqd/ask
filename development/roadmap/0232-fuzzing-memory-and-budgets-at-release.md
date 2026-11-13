---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0232 — Fuzzing, memory back under budget, budgets checked at every release

Engineering plan phase E; the owner (2026-11-13): budgets checked on every release.

1. Fuzzing the byte parsers (SSE, session framing and recovery, MCP framing, terminal input) with libFuzzer, scheduled in CI; each
   crash becomes a red test.
2. Memory: idle 19.3 MB against 15, active 29.8 against 25 (2026-11-13). Allocation traces of both, then the fix, measured.
3. `Scripts/measure-budgets.py` runs as a release gate (roadmap 0070): a release over budget does not ship. Cold start and action
   delay measured on an unloaded machine for the record (t14, t26).

## Done when

Fuzzers run weekly with no open crash, memory is under budget, and the release workflow runs the budgets.
