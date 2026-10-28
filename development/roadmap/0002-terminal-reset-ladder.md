---
status: done
blocked-by: 
date: 2026-10-18
---

> **The application half moved to [0006](0006-apply-the-reset-ladder.md).** The ladder's bytes and its
> model are TerminalKit's and were verified there; what was owed here — applying it on teardown and on
> signal — is now tracked, and partly done, in `0006`. `0006` is the live entry for this work.

# 0002 — The tiered terminal reset ladder

Give the terminal stack a recovery primitive. Today `restoreMode()` restores only `termios`, so a
crash leaves the user's shell in the alternate screen with mouse reporting and bracketed paste still
enabled.

Escalating, cheapest first:

1. Selective cleanup — leave alt screen, disable mouse and bracketed paste, `ESC[m`, show cursor.
2. DECSTR soft reset, `CSI ! p` — resets modes, cursor and attributes while preserving screen
   contents and scrollback.
3. RIS full reset, `ESC c` — destroys scrollback. Last resort only.

**Not blocked by the extraction.** This is new behaviour, not moved code, so it landed before the
move existed. ADR-0001 had this entry blocked behind the extraction, which was wrong.

This entry now lives in **TerminalKit**, which owns the code; it is kept here because `ask` is where
the need was identified. TerminalKit's roadmap 0002 carries the outstanding work.

## Done

- **`TerminalKitCore` landed** (Aemi `03ac1d5`, moved out as `d0f8108`): all three tiers, the escalation order, and nine
  byte-exact tests written before the implementation and confirmed failing on the missing API first.
- The tests caught two malformed escape sequences in the first draft — `ESC [ ? 1006 l` and
  `ESC [ ? 2004 l` were each a byte short, which would have left mouse reporting and bracketed paste
  enabled after a crash. That is the exact failure this entry exists to prevent.

## Still owed

**Oracle tests added** — `TerminalStateModel`, an independent model written from the specification,
driven with the real bytes. Eight tests. They found a bug in the oracle itself: mode 25 is inverted
relative to other private modes, and the model had it backwards.

**Measured against four real terminals**, via DECRQM, each launched as `-e /bin/sh -c` so no shell
configuration could contribute escape sequences. Tier 1 passes on kitty, ghostty and wezterm.

**It refuted us.** DECSTR resets no DEC private mode on any of them, which the oracle and these docs
had asserted. TerminalKit's ADR-0002 corrects the oracle and the tier documentation.

**Still unmeasured: scrollback preservation.** DECRQM reports modes, not history, so that claim still
rests on the tiers emitting no `ESC c` plus the oracle. Terminal.app answers no DECRQM and is
inconclusive. See TerminalKit roadmap 0002.

**Remaining scope:** applying the ladder on teardown and on signal, so the normal path writes the
selective tier and only escalates when the cheap tier demonstrably failed.

## Closed (2026-10-18)

Its remaining scope moved to `0006`, which is done. Nothing is owed here.
