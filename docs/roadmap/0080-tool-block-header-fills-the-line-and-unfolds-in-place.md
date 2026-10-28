---
status: not-started
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

## Open questions

- Prefixes for other tools: proposed in the 2026-10-28 reply, awaiting the owner. Nothing is implemented for them.
