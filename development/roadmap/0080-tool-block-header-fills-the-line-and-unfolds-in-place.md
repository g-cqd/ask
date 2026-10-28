---
status: done
blocked-by: []
date: 2026-10-28
---

# 0080 — Tool block header fills the line and unfolds in place

Owner request, from `ask-wishes.md`. The header row of a tool block carries the tool command, and the block
status trails it. Today the command is not laid out to use the width, and unfolding repeats the command.

Not related to 0078 (semantic payloads, deprioritised): this changes only the header row and the fold, not the payload.

## Still owed

- The command takes the whole header row, up to the spacing before the trailing status component.
  - A command wider than that is cut with an ellipsis (`…`), counted in display cells, not characters.
- Unfolding does not print the command a second time. The first header line stays, and the command's remaining
  lines open from that first line, inside the same block.
- The timeout moves in front of the command as a prefix: `shell · timeout 2m · <command>`; without a timeout the
  prefix is only `shell · <command>`.
  - The time is pretty printed for the user's locale.
  - A config setting chooses compact or pretty time, or the existing style setting is reused if one already
    fits. Decide which when starting, and record it here.
- Tests: header width at several terminal widths, wide characters, a very long single-line command, folded and
  unfolded states, and the timeout prefix with and without a timeout. Check in a PTY probe that nothing wraps.

## Result (2026-10-28)

- Decision: the existing `ui.localizedDurations` switch is reused, with no new key. On (the default), limits read `timeout 2 min`; off, a
  clock: `timeout 2:00`. The yield, when the call sets one, joins the prefix too: `shell · timeout 2 min · yield 5 sec · <command>`.
- Folded, every tool header is one row. Text past the gap before the status is cut with `…`, counted in display cells; a selection copies
  the shown text, not the ellipsis. A multi-line command shows its first line and ` …`. The gap before the status is now two cells for
  every header (it was four).
- Open, the command's first line stays on the header row and its other lines continue below; the command is not repeated. A blank row
  separates it from the output. Embedded heredocs still fold: the toggle sits on the command's own line.
- Owner follow-up, 2026-10-28: an open command is drawn at full brightness, in the terminal's own foreground. The lead (`shell · timeout …`),
  the status and the output keep their dim status style. Folded headers are unchanged.
- Tests: `CommandHeaderTests` (widths 20 to 300, wide characters, long single line, folded and open, the prefix with and without limits,
  locale units, selection text, heredoc toggles, brightness). The brightness test failed with the change disabled. `BlockStatusLayoutTests`
  now expects one row.
- PTY: `Scripts/probe-command-header.py` (11 checks) and the updated `probe-tool-input.py` and `probe-folding.py` pass against the release
  binary. This used the pyte emulator, not a physical terminal. pyte does not keep faint, so brightness is checked from the SGR bytes.

## Open questions

- Prefixes for other tools: proposed in the 2026-10-28 reply, awaiting the owner. Nothing is implemented for them.
