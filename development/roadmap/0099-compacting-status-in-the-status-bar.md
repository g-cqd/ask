---
status: done
blocked-by: []
date: 2026-10-28
---

# 0099 — "Compacting..." in the status bar

Owner wish (2026-10-28 16:57): while compacting, the leading component of the status bar (where the spinner is) says `Compacting...`; the text
and the spinner are purple; one space separates the spinner from the text.

## Result (2026-10-28)

- A new loop event, `compacting`, comes just before the summary request; the screen's `ConversationUpdate.compacting(true)` sets
  `ScreenState.compacting`, and the end of the compaction (`compacted` or `compactionFailed`) or of the run clears it. Replays never show it.
- While it is set, the status bar's leading mark is the spinner, one space, and `Compacting...`, all in purple (ANSI magenta, so it follows
  the terminal's palette), and the spinner turns. The mark's colour now covers its whole width, sized after any clipping of the line.
- Tests: `CompactingStatusTests` (mark, colour span, end, narrow width), the event's order in `AgentLoopCompactionTests`. Not run against a
  live provider's compaction.
