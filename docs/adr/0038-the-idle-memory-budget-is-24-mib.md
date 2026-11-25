---
status: accepted
date: 2026-10-20
---

# 0038 — The idle-memory budget is 24 MiB

## Context

`AskCore.Budget.idleMemoryMebibytes` was 8, set when the binary held no agent: 5,712 KiB measured, as that comment records. Its own doc
comment called it "the one budget that should never grow at all". It has been exceeded since long before the Codex work
(roadmap 0028 item 7: 8,208–8,264 KiB; ADR-0034: 8,896–8,912 KiB), so `ask --budgets` and the measurement harness
reported OVER BUDGET on every run and a failing gate told nobody anything new. No ADR owned the number: it lived only in that
comment.

The owner asked for it to be raised to 24 MiB. No reason was given with the request, and none is invented here.

## The probes

Ledger in `development/diary/2026-10-20-29.md`.

- **Does the interface report the new limit?** `ask --budgets` from the changed build prints `"idleMemoryMebibytes":24`; the
  `main` build prints 8. **CONFIRMED.**
- **Does the harness verdict change, and only that?** Four runs of `Scripts/measure-budgets.py` (12 runs each) on the changed
  build: idle memory 9,240–9,280 KiB median against a 24,576 KiB limit. Three of the four runs reported all four budgets
  within limits. The first run reported cold start 55.9 ms, input delay 5.76 ms and action-to-action 4.65 ms over their
  limits; it was not reproduced by an interleaved comparison with the unchanged `main` build, nor by the next three runs.
  Cause **unknown** (**INCONCLUSIVE**); the machine's load average was 60–140 throughout, from other agents' work.
- **Does the change cost anything?** It cannot: the constant is read only by `--budgets`. Interleaved 12-run comparison with
  `main`: medians within noise, ranges overlapping. No performance claim.

## Decision

1. `Budget.idleMemoryMebibytes` is 24. The other three budgets are unchanged.
2. How it is measured is unchanged: median of the harness's runs, resident set size over a PTY, a 120×40 window, isolated
   configuration. A test pins the value, so moving it again means editing the test and writing down why.
3. It is a ceiling that catches a gross regression, not a target. The rule that a change which can add memory carries its
   before-and-after numbers is untouched (white paper, "Every change that can affect performance is benchmarked").

## Consequences

- The gate now has room: about 9.3 MiB is measured, so roughly 15 MiB of regression would pass it. A regression of a few hundred
  KiB, which the 8 MiB limit could not distinguish from the existing overrun anyway, is now caught only by the per-change
  numbers, not by the gate. That is a real loss of sensitivity, accepted by the owner.
- The harness checks medians only. Cold-start p95 under load has exceeded 25 ms (26.9 and 27.2 ms in one comparison) while the
  median passed; that is unchanged and not addressed here.
- Roadmap 0007's idle-memory half ("re-derive it from measurements") is closed by decision rather than by derivation. Whether
  resident size or physical footprint is the better measure, which 0007 raised, is still open and unmeasured on this build.
- The CI `budgets` job, which has never run, would no longer fail on idle memory.
