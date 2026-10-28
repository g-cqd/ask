---
status: done
blocked-by: []
date: 2026-10-28
---

# 0104 — The compaction threshold as a share of the model's window

Owner request (2026-10-28): automatic compaction should work with a ratio.

## Today

`compactAt` is a token count, 150,000 by default, capped by `ContextBudget` at what fits the window (window minus the reply minus a margin of a
tenth of the window, at least 4,096). So a 1M-token model compacts at 15% of its window, and a 200K one at 75%.

## Plan

- `compactAt` also takes a share of the window: `"75%"` in a file, `--compact-at 75%`, `ASK_COMPACT_AT=75%`. A whole number stays a token
  count; `0` stays "only when the window is full".
- The default becomes a share. Proposed: `"75%"`, which keeps today's behaviour on a 200K window. Owner to confirm the number.
- With no window known, a share falls back to the token default (150,000), and `ask config` says so.
- The cap stays: whatever is asked, compaction starts before the next request would not fit.
- Tests on `ContextBudget` and on parsing (file, flag, environment, a share over 100% refused).

## Result

`CompactionThreshold` is `.share(1...100)` or `.tokens(n)`. A file takes `"75%"` (a string) or a number; `--compact-at` and `ASK_COMPACT_AT`
take either, and a bad environment value is named and ignored. The default is `75%`, **pending the owner's confirmation**. At launch the share
is taken of the window the model metadata gives (150,000 tokens when none is known), and once the server shows a window during a run the
same share is taken of that (`AgentLoop.budget(for:window:)`); the cap still applies. `ask config` prints "75% of the model's window".
Tests: `CompactionThresholdTests`, plus the configuration suites updated.
