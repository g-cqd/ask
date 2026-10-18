---
status: done
blocked-by: ["0001", "0002", "0003"]
date: 2026-10-18
---

# 0004 — Measure the four budgets before optimising anything

Set the numbers `ask` will be held to: **cold start**, **idle memory**, **input delay**, and
**action-to-action delay**.

## Measured — first baselines

`Scripts/measure-budgets.py` spawns the release binary on a PTY and times the prompt appearing in the
output stream. The program reports nothing about itself: a program that reports its own latency
reports the flattering number.

| Budget | median | p95 | min | max |
|---|---|---|---|---|
| cold start | **11.06 ms** | 13.77 ms | 6.28 ms | 17.05 ms |
| idle memory | **5,712 KiB** | 5,712 KiB | 5,696 KiB | 5,728 KiB |
| input delay | **0.12 ms** | 0.18 ms | 0.08 ms | 0.23 ms |
| action-to-action | **0.05 ms** | 0.07 ms | 0.03 ms | 0.08 ms |

12 runs, release, on this machine. The harness was probed against a binary that never prints its
prompt and correctly reported no successful runs, so it is not a harness that always agrees.

**Read the fourth number carefully.** Action-to-action at 0.05 ms measures Enter producing the next
prompt in a program with no agent in it. It is a real measurement of a trivial action, and it is
**not** yet the number a user feels between a tool running and its result appearing. That arrives
with the agent loop.

## Targets and a guard — done

`Budget` (in `AskCore`) states each budget as a number with headroom above the measurement, so
ordinary variance cannot fail the gate:

| Budget | measured median | limit |
|---|---|---|
| cold start | 11.06 ms | **25 ms** |
| idle memory | 5.58 MiB | **8 MiB** |
| input delay | 0.12 ms | **2 ms** |
| action-to-action | 0.05 ms | **2 ms** |

`Scripts/measure-budgets.py` now reads the limits from the binary itself — `ask --budgets` prints them
as JSON — so there is exactly one definition and a script copy cannot drift. It reports a verdict per
budget and **exits non-zero when any is over**.

Both were probed rather than trusted: tightening the cold-start limit to 1 ms fails three unit tests
and makes the harness exit 1; restoring it returns both to green.

## Still owed

- **CI runs the harness.** The guard exists and is wired to the measurement, but the workflow does
  not invoke it yet, and these numbers are macOS-hardware-specific so the job needs a fixed runner.
- **The action-to-action budget is provisional.** It measures a trivial action in a program with no
  agent. When the loop lands it must be re-derived, and the stale number must not survive.

**Notes:** no number in this project is a guess. Until this entry lands, "ultra-performance" is an
unmeasured claim and nothing may be justified by it. Percentiles, not averages; median and spread,
never the best run. Interleave before-and-after runs so background load cancels out of the ratio.