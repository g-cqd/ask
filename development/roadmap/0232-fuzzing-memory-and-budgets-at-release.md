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

## Step 2: measured, waiting for a decision

Idle is 17.3–17.9 MB resident on mbp23, 5.6 MB of it ask's own. About 3.1 MB is what linking AppKit, PDFKit, AVFoundation
(0.9 MB) and FoundationModels (2.6 MB) costs before any call; the heap and the threads are not the excess. Under 15 MiB needs
those loaded on first use (the model in a helper or a lazy library), or a different budget: the owner's choice.

## Done when

Fuzzers run weekly with no open crash, memory is under budget, and the release workflow runs the budgets.
