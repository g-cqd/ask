---
status: in-progress
blocked-by: []
date: 2026-10-22
---

# 0054 — Diagnose cold-start variance with the terminal setup fixed

The combined shipping tree's last 12-run sample measured cold start at 27.08 ms median against 25 ms.
A matched interleaved sample measured unchanged remote main at 26.18 ms and the combined tree at 24.82 ms;
other samples on the same candidates were much faster. This does not establish a code regression or a clean
absolute-budget result. Evidence, including all failures, is in diary 2026-10-22 (03).

The budget harness now sizes the child's PTY before exec, as the action/cache harnesses already do. A deterministic
recording-double probe failed both setup-order assertions before that fix and passed afterward. Remaining variance
must not be attributed solely to that corrected race or to host load without evidence.

## What lands

- Reproduce with fixed child-side terminal geometry, isolated configuration/state, shipping binaries and a recorded
  host workload. Keep incomplete starts and failed runs visible rather than dropping them from the result.
- Trace startup phases to distinguish application work, process scheduling and first-frame delivery; measure the
  tracing overhead and do not treat the instrumented executable as the shipping result.
- Use fixed-count interleaved control/candidate samples; report medians, tails and spread, not a selected green run.
- Fix a measured application cause if found, with regression evidence. Otherwise document the observed platform or
  workload boundary and a reproducible budget-verification method. Do not silently relax the 25 ms limit.
