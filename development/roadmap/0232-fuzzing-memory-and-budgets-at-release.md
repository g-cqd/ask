---
status: in-progress
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

## Step 1: done (2026-11-14, diary 2026-11-14-04)

`Fuzz/` (one libFuzzer executable, six targets: `sse`, `session`, `mcp`, `terminal`, `index`, `text`), `Scripts/fuzz.sh`, and
`.github/workflows/fuzz.yml` weekly. ask's modules are instrumented by `ASK_FUZZ` in the manifest; the whole graph was too slow to
instrument. Four defects found and fixed test-first, each input now a seed: `LineSplitter` and `SSEDecoder` applied their limit
differently to a whole line and a cut one; a forge item's state and address could start a section. 300 s of all six is clean.

## Step 2: done (2026-11-14, diary 2026-11-14-04 and -05)

Two causes. The status bar's read of GitHub at the start loaded the network stack into an idle ask (5.9 MiB): it is now read by a
child process (ADR-0152). About 3 MiB is what linking AppKit, PDFKit, AVFoundation and FoundationModels costs before any call:
the owner chose to change the budget rather than load them late (ADR-0151: 24 MiB idle, 30 active). Under the gate: idle
22.4 MiB before, 17.2 after; active 27.6; all five budgets hold.

## Done when

Fuzzers run weekly with no open crash, memory is under budget, and the release workflow runs the budgets.
