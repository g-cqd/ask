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
in `development/research/startup/README.md`.

Diary 2026-10-22 (05) records the phase/cadence experiments, instrumentation comparison and rejected runtime
changes. A warning-pressure same-artifact cohort measured paced/burst cold medians of 31.46/17.35 ms; a normal-
pressure repeat measured 16.92/16.14 ms, with large tails retained. Most traced CPU precedes the CLI configuration
marker; model lookup/policy and frame output do not explain the whole range. No unique hardware mechanism or
application regression is established, and no runtime optimization is adopted.

## Found, not fixed (diary 2026-10-22 (09))

Slow cohorts are slow because the process uses more CPU, and the share of launches that begin on an **efficiency core**
predicts the cohort median (Spearman +0.93 over 25 cohorts). Efficiency-core starts took about 24 ms against 12.5-13.7 ms on
performance cores, in both paced and burst launches, replicated in a second run of 300 launches. Host load, page-ins and
the two performance clusters do not explain it. On the latest main a paced cohort measured 13.32 ms (within budget).

This is an association, not a demonstrated cause: the one experiment that tried to set the QoS of the launch failed its
own manipulation check (the main thread saw QoS 21 in every arm), and a slow performance-core cohort from an earlier,
heavily loaded run is still unexplained.

## Startup CPU (diary 2026-10-23 (13), ADR-0065)

Delivered: a bare launch skips ArgumentParser's reflection, saving a median 0.9-1.1 ms of CPU per launch (about 7%), with
guards that keep it the same launch as a parsed empty command line. Five other levers were measured and refuted (chained
fixups, async main, library count, page faults, a size-optimised build). A profile of 60 launches puts 26% of samples in the
loader resolving ask's 2,020 imported symbols and 24% in system initializers that any Foundation program pays.

## Still owed

- Decide, with the owner, how budget verification should treat the efficiency-core share (ADR-0038 set the budgets):
  report it beside the median, require it to be low, or leave the budget as is. Nothing was relaxed.
- The loader's symbol resolution is the largest ask-specific cost left. Find how many of the 2,020 imports come from code a
  bare launch never reaches before deciding whether a smaller binary surface is worth its complexity.
- Run a QoS intervention that really reaches the process (for example `taskpolicy`), compare terminal launches with the
  harness's, and sample the memory-pressure warning level, which no cohort has reached.
