---
status: accepted
date: 2026-10-24
---

# 0077 — A double or triple click in the input takes a word or a line, by the transcript's rules

## Context

A drag in the input selects text (ADR-0076) and a click places the cursor (ADR-0071), but a double or triple click in the input only
placed the cursor, while the same gestures in the transcript take a word and a line (ADR-0030).

## Decision

- **The rules are the transcript's, not new ones.** The draft is presented to TerminalKit's `ContentSelection.word` and `.line` as one
  block of hard lines (split at `\n`, tabs left as they are, so an offset in the line is an offset in the draft). A double click takes the
  run of like characters under the pointer (letters, digits and `_` together, spaces together, anything else together); a triple click
  takes the hard line without its line break. A cell past the end of a line takes the last run, as in the transcript; an empty line takes nothing.
- The result is an ordinary input selection (ADR-0076): highlighted, cursor at its end, copied if `ui.copyOnSelect` is on, replaced by
  typing, deleted by Backspace, copied by Ctrl+C. A click elsewhere drops it.
- **A click that changes the selection must not make the pointer forget it was a click.** Placing the cursor and taking a word used to
  go through the call that also resets the pointer recognizer, which made every click in the input a *first* click and no double click
  ever formed. They now drop the selections without touching the recognizer; only a key or a paste, which end any gesture, reset it.
- A waiting approval question and `ui.mouse false` still block it.

## Consequences

Word and line selection in the input behave as they do above it, with one rule set to learn. Keyboard selection (Shift+arrows), cut and
a wheel for the input's own window are still not done. A word is by hard line, not by display row, so a long wrapped word is one word.
