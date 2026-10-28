---
status: accepted
date: 2026-10-23
---

# 0070 — A click on a picker row is the choice and Enter in one gesture

## Context

ADR-0067 and ADR-0069 built the `/` and `@` pickers keyboard-first and left the rows unclickable, and said the wheel scrolls the
transcript. Roadmap 0048 lists "clicking a row" as owed; roadmap 0051 gives the screen one pointer model, in which a click means what
was drawn.

## Decision

1. **A click with the left button on a match row chooses it and inserts it, exactly as Enter does.** The row's text goes into the draft
   where the word was, with the trailing space, and nothing is sent. A line range typed after a file path is kept. The result is the
   same draft Enter would leave, so a second Enter sends or runs it.
2. **Only match rows are targets.** The title, the status line, the prompt and the transcript keep the meanings they had. The wheel
   over the list still scrolls the transcript, and a drag that starts on a row selects and inserts nothing.
3. **The frame says what a row is.** The composer records, with the rest of the frame's geometry, the row of the first match, which
   matches were drawn (the window, which scrolls) and the word the list was for. A click is resolved against the newest frame at the
   moment the button comes up, as every other click is.
4. **A click on a list that has moved on is ignored.** If the list now belongs to another word, or a question has taken the keys, the
   click meant a row that is no longer there. The driver can hand over a frame older than the state (a key arrived in between); the
   word recorded in the frame is compared with the picker's before anything is inserted.
5. **Any click count counts.** A fast second click on the same row finds the list closed and the frame redrawn, and does nothing.
6. **Nothing is added to the list's drawing.** No hover, no mark, no pointer: ADR-0044's text-only rule stands, and the title is
   unchanged. With `ui.mouse` off nothing is reported, so nothing is clicked, and the keys are the only way as before.

## Consequences

The picker's rows are reachable by pointer without a mode: a click needs no focus and no second step. The cost is one more region in
the pointer's map, built only while the list has rows.

## Not decided here

A hover or a click on the title to close the list; clicking the detail of a row; touch.

## Probes

Unit tests with the pointer rig (the same composer and controller the screen runs), a real-binary PTY probe with a negative control
(`Scripts/probe-picker-click.py`), and mutants on every line of the click path. Results are in diary 2026-10-23 (19).
