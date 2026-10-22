---
status: accepted
date: 2026-10-22
---

# 0059 — The input uses the kit's display map with a host row cap

## Context

Roadmap 0049 left Up/Down operating on hard lines while the renderer wrapped them. The renderer also owned a fixed six-row cap and
recorded a caret before wrapping its next character, which could place that caret one cell outside the terminal. TerminalKit ADR-0032
now provides one grapheme-safe display-row map and a bounded viewport; ADR-0046 already chose ask's input-height policy.

## Decision

- ask adopts `InputLayout` and `InputViewport` from TerminalKit. `PromptLayout` supplies `ask> `, caches the map until text or width
  changes, and keeps the last viewport top. It contains host policy, not another wrap implementation.
- `ui.promptRows` is a positive integer, default **6**. Effective height is capped at a third of the terminal and leaves room for the
  existing status row. At least one input row remains on tiny terminals; a one-row terminal omits status, and an empty dimension
  produces no content. The ASCII prefix clips on narrow terminals to leave an editable cell.
- The cap limits **drawn display rows**, never the source text. A clipped input reports `input 8–10 of 10` in the existing status row,
  without adding a row. That cue precedes the model label so a narrow terminal cannot silently hide it behind a long label.
- The driver passes the terminal width on every key and updates it after resize. Up/Down use the same map as rendering, retaining a
  wanted display-cell column across short rows and snapping before wide graphemes. Sideways editing or a width change resets the goal.
- Existing `PromptEditor.apply` callers that omit width retain hard-line navigation. Home/End and Ctrl+A/E/U/K remain hard-line
  operations in both modes. Ctrl+X clears the **entire** unsent draft; it is not clipboard cut and never submits it.
- Enter submits the original complete source text after editing, not the visible slice or expanded tab/replacement display text.
- Like the other implemented `ui.*` keys, the row setting is read at screen startup; re-exec reload reads it again. This does not add
  live screen-option updates, an environment variable or a command-line flag.

## Consequences

The old renderer-specific prompt walker is removed. Input layout remains O(source/rendered bytes) on a text or width change; cursor
lookup and viewport updates are cached, while a display-aware vertical move currently rebuilds its map. That cost is measured, not
assumed free. The editing model remains ask's existing one rather than mixing a `TextBuffer` migration into this behaviour change.

Input mouse placement, wheel scrolling and selection, and sustained transcript-edge autoscroll are still separate roadmap 0019/0051
work. Physical keyboard/terminal verification is not implied by a PTY probe. Evidence is in diary 2026-10-22 (6).
