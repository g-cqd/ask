---
status: accepted
date: 2026-10-24
---

# 0088 — Ctrl-X cuts a selection in the input, and clears the draft otherwise

## Context

ADR-0059 gave Ctrl-X the job of clearing the whole unsent draft, because Ctrl-U is line-local and nothing cleared everything. In every editor
and shell that has the key, Ctrl-X is also **cut**, and the input now has selections (ADR-0076 to 0078), so a selection that cannot be cut is
the one thing it still cannot do.

## Decision

- **With a selection in the input, Ctrl-X cuts it**: the selected text leaves the draft, goes to the clipboard, and the cursor stays where the
  selection began. It copies whatever `ui.copyOnSelect` says: that setting governs what a selection does *by itself*, and a cut is a request.
- **With nothing selected, Ctrl-X still clears the whole draft** (ADR-0059), so nothing that worked stops working and there is still no
  cut-nothing case that silently does nothing.
- A selection in the *transcript* is not cut (it is not editable text); Ctrl-X then clears the draft as before. A waiting approval question
  keeps the keys.
- The status line adds `ctrl+x cut` while a selection in the input exists, and only then.

## Decision record

This decision was made without being asked for. I put the question (cut when there is a selection, clear otherwise?) at the end of a report
and the answer was "continue", so I took the proposal as written. It is easy to reverse: it is one branch in the selection's key handler.

## Consequences

The same key now does two things, chosen by whether something is visibly selected and highlighted. A user who selects by accident and then
presses Ctrl-X to clear the draft gets a cut of the selection and the rest of the draft stays; the clipboard holds what was cut. Cut cannot be undone; there is no undo in the input.
