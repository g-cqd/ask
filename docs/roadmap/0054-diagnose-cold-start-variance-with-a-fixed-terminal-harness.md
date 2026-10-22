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

## Delivered

- Reproduce with fixed child-side terminal geometry, isolated configuration/state, shipping binaries and a recorded
  host workload. Keep incomplete starts and failed runs visible rather than dropping them from the result.
- Trace startup phases to distinguish application work, process scheduling and first-frame delivery; measure the
  tracing overhead and do not treat the instrumented executable as the shipping result.
- Use fixed-count interleaved control/candidate samples; report medians, tails and spread, not a selected green run.
- Fix a measured application cause if found, with regression evidence. Otherwise document the observed platform or
  workload boundary and a reproducible budget-verification method. Do not silently relax the 25 ms limit.

## Evidence and outcome

`34b18ea` corrects the benchmark's before-fork/full-frame boundary, optional trailing blank, missing cohorts and
small-sample p95. Seven deterministic guards and five behavioral mutants are recorded in diary 2026-10-22 (04).

`Scripts/measure-startup.py` retains fixed cohorts, alternating binary or same-artifact cadence controls, phase
markers, lifetime CPU/resource counters, host snapshots and artifact fingerprints. Traced, incomplete or changed
artifacts cannot certify a shipping budget. The disposable phase overlay and complete reproduction method are
in `docs/research/startup/README.md`.

Diary 2026-10-22 (05) records the phase/cadence experiments, instrumentation comparison and rejected runtime
changes. A warning-pressure same-artifact cohort measured paced/burst cold medians of 31.46/17.35 ms; a normal-
pressure repeat measured 16.92/16.14 ms, with large tails retained. Most traced CPU precedes the CLI configuration
marker; model lookup/policy and frame output do not explain the whole range. No unique hardware mechanism or
application regression is established, and no runtime optimization is adopted.

## Still owed

The cause is not found. The final shipping cohort at unchanged runtime sources measured cold p50 31.01 ms (28.59-33.03,
20 of 20 complete): over 25 ms with a tight spread. A same-artifact paced/burst cohort at the same pressure level
passed at 13.98 ms, and a generic fixed-work control rules out a plain idle-gap slowdown (diary 2026-10-22 (05)).
Untested candidates: page-cache/dyld state of the binary and frameworks after idle under memory pressure, dyld
work specific to ask, and worker-thread startup. Probe each with the fixed-cohort tool before changing code. Do not
relax the 25 ms limit, and do not call the method's delivery a budget pass.
