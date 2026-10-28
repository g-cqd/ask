---
status: done
blocked-by: []
date: 2026-10-28
---

# 0120 — "Reconnecting..." in the status bar instead of a retry block

Owner request (2026-10-28 22:40): when the connection drops, say "waiting for reconnection..." or "reconnecting..." without a message in the
conversation's blocks.

## Result (2026-10-28)

- A `retrying` event no longer adds a notice. It sets `ScreenState.reconnecting`, and the status bar's leading mark becomes the spinner,
  one space and `Reconnecting...`, in the warning yellow, as `Compacting...` is purple (0099). Compaction wins if both apply.
- It ends when the model is back (streamed text or thinking, a tool, a usage update) or the run ends; other updates leave it.
- The retry's reason and wait are kept as a detail, shown only with `--verbose`. Print mode still writes them to standard error.
- Tests: `ReconnectingStatusTests`. PTY: `Scripts/probe-reconnecting.py` with a provider that answers 529 with `retry-after: 2` once,
  against the release binary: the mark shows while waiting, no block mentions it, the mark goes with the answer. pyte, not a real terminal.
