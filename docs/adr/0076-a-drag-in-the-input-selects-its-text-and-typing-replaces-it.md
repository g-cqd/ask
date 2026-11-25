---
status: accepted
date: 2026-10-23
---

# 0076 — A drag in the input selects its text, and typing replaces it

## Context

Clicks place the cursor in the input (ADR-0071), but a drag there selected nothing. The transcript's selection (TerminalKit's
`SelectionController`) is anchored in *content blocks* and has no notion of an editable draft whose text and cursor change under it.

## Decision

- **A selection in the input is a range of character offsets in the draft**, kept in `ScreenState.inputSelection`, not a second use of
  the transcript's content model. A drag is an `InputDrag`: the press and the head, each as the offset before and after its character,
  so a drag includes the character under the pointer at both ends in either direction, and the pressed cell alone selects nothing
  until the pointer has left it.
- **The editor's cursor follows the end being dragged.** That makes the existing "cursor stays in the window" rule do the scrolling: a
  drag held at the first or last drawn row, with more rows of the draft that way, steps the head one display row per tick (the same
  50 ms timer and `tick()` as the transcript's edge scroll, ADR-0061), at the column it had, and the window follows.
- **The highlight is exact per drawn row** (`PromptLayout.highlight`): from where the selection starts on that row, or its first cell
  (after the prefix on the first row), to where it ends, or its last; a line break and the blank after a row's last character are not
  selected. No array is built when nothing is selected, which is the common frame.
- **Keys: a selection takes Ctrl+C (copy, then clear) and Escape (clear) before the editor**, like the transcript's (ADR-0056).
  Backspace and Ctrl-D delete the selection and nothing more. A key that would type text, and a paste, replace it. Any other key drops
  it and then does what it always did. "Types text" is the editor's own rule (`PromptEditor.insertsText`), so a selection is replaced
  by exactly the keys that would have typed something.
- **Copy on select** follows `ui.copyOnSelect`: on release the selected text goes to the clipboard, the highlight stays, and the
  status line explains Ctrl+C and Escape, as for the transcript. Starting a drag in the input drops a selection in the transcript, and
  the reverse.
- A waiting approval question owns the pointer and the keys: nothing is selected while it waits. With `ui.mouse false` nothing is heard.

## Consequences

The two selections are separate models on purpose. Both are cleared by the same call, so they cannot both be visible. **Not done:** double
and triple click to take a word or a line in the input, Shift+arrows, selecting with the keyboard, cut (Ctrl-X still clears the whole
draft, ADR-0059), and a selection that survives the draft being replaced underneath it (it is clamped to the text, and cleared by any
key). A text change that does not come from a key or a paste (a returned queued prompt) can leave a stale range, which is clamped.
