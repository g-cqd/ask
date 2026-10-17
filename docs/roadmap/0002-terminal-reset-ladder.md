---
status: in-progress
blocked-by:
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

**Not blocked by the extraction.** This is new behaviour, not moved code, so it lands in Aemi before
the move exists. ADR-0001 had this entry blocked behind the extraction, which was wrong.

## Done

- **`AemiTerminalCore` landed** (Aemi `03ac1d5`): all three tiers, the escalation order, and nine
  byte-exact tests written before the implementation and confirmed failing on the missing API first.
- The tests caught two malformed escape sequences in the first draft — `ESC [ ? 1006 l` and
  `ESC [ ? 2004 l` were each a byte short, which would have left mouse reporting and bracketed paste
  enabled after a crash. That is the exact failure this entry exists to prevent.

## Still owed

**A PTY-backed test.** The nine tests prove the bytes emitted. They do not prove that a terminal
behaves as each tier claims — that DECSTR preserves scrollback, that selective cleanup really leaves
no private mode set. That is the remaining work, and it is the half that matters to a user.

**Remaining scope:** applying the ladder on teardown and on signal, so the normal path writes the
selective tier and only escalates when the cheap tier demonstrably failed.