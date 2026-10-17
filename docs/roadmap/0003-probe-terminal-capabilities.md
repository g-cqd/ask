---
status: not-started
blocked-by: ["0001"]
date: 2026-10-18
---

# 0003 — Probe the terminal instead of guessing at it

`TerminalCapabilities` decides what the host can do from `KITTY_WINDOW_ID` and `TERM_PROGRAM`. Those
are hints, not proof, and they cannot see whether the terminal supports DEC 2026 or the kitty keyboard
protocol.

**Done when:** capabilities are established by actively querying the terminal, the answer is cached
for the session, and the probe is itself tested against a mock terminal that answers correctly, lies,
and times out.

**Notes:** the keyboard-protocol question is not only about capability. Enabling the kitty keyboard
protocol is the fix for ESC-ambiguity latency, which is one of the four performance budgets. The
measurement comes after this entry lands, not before.