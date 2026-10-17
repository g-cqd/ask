---
status: not-started
blocked-by: ["0001"]
date: 2026-10-18
---

# 0002 — The tiered terminal reset ladder

Give the terminal stack a recovery primitive. Today `restoreMode()` restores only `termios`, so a
crash leaves the user's shell in the alternate screen with mouse reporting and bracketed paste still
enabled.

Escalating, cheapest first:

1. Selective cleanup — leave alt screen, disable mouse and bracketed paste, `ESC[m`, show cursor.
2. DECSTR soft reset, `CSI ! p` — resets modes, cursor and attributes while preserving screen
   contents and scrollback.
3. RIS full reset, `ESC c` — destroys scrollback. Last resort only.

**Done when:** all three tiers are implemented, the ladder is chosen automatically on teardown, and a
PTY-backed test proves that after each tier the terminal is in the state the tier claims: modes off,
no leftover private modes, cursor sane, and — for tiers 1 and 2 — scrollback intact.

**Notes:** written red-first against a PTY, per the white paper's terminal doctrine. The claim that
DECSTR preserves scrollback is **not yet probed** on every terminal `ask` will meet; the test proves
it for the harness, and the open question stays open until it is probed against real terminals.