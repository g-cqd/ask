---
status: done
blocked-by: []
date: 2026-11-08
---

# 0214 — The input in a box, in the session's colour

The owner, 2026-11-04 (note n36, task t217): the input's rules should not run edge to edge. They should join with corners and a
vertical border on each side, dimmed or in the session's tint, lighter. The owner chose on 2026-11-08:

- a setting, `ui.inputBorder`, with `"tint"` the default;
- the command and file lists above the box;
- rounded corners.

## The plan

- `ui.inputBorder`: `"tint"`, the session's hue mixed 60% from the page (`ScreenTheme.inputBorder`), or `"dim"`, the grey of
  secondary text. A session with no colour yet draws the grey.
- With `ui.separator` on, `InputBox` draws `╭─╮`, `│ … │` and `╰─╯` on the rows the two rules took. The input is four columns
  narrower and starts two columns in. The pickers, questions and approvals open above the box.
- Clicks, drags and selections in the input subtract the box's inset (`FrameGeometry.promptColumn`).
- Up and Down move by the rows as drawn: the frame's `InputLayout.columns`, not the screen's width. This also fixes the input beside
  the sidebar's bottom band, which moved by the screen's width before.

## Done when

- `InputBoxTests` (7) and `InputBorderConfigurationTests` (2): red before the change.
- `InputLookTests` and `SidebarBandTests` are updated to the box.
- The probes read the input through the box (`probe_screen.unboxed`, `is_box_edge`): `probe-input` keeps its draft widths by
  widening each screen by four columns. `probe-thread-question-pop` waits for the whole question, not its first row; it read
  frames part way through. `probe-files` ends the list at the box's edge; otherwise it took the edge for a file and stopped waiting
  for the listing (5 of 5 runs pass). The sweep passes 92 of 93 with `probe-files` failing once before that fix.
- `docs/screen.md` and `docs/configuration.md` say so.

## Not verified

The look in a real kitty or Ghostty, light and dark pages.
