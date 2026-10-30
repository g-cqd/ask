---
status: done
blocked-by: []
date: 2026-10-28
---

# 0111 — Prompt history with Up and Down

Owner wish (2026-10-28 19:22): Up and Down browse previous prompts so one can be reused. Once a recalled prompt is edited, moving to a more
recent one is no longer possible. `/` commands are included in the history.

## Still owed

- Where the history comes from: the session's prompts, and whether it spans sessions in the project.
- Up only recalls when the cursor is on the input's first row (Down on its last), so multi-line editing keeps its arrows.
- The edit rule exactly as asked: after an edit, Down does not go to newer entries; define what Down does then (nothing, or the draft).
- The draft being typed before browsing is kept and comes back at the newest end.
- Tests for recall, edit, multi-line inputs and commands.

## Done (2026-10-29)

- **Source:** what this screen sent (prompts and `/` commands, as typed) and the prompts of a resumed session, in order; not other sessions
  of the project. At most 1,000 entries; an empty line or a repeat of the newest is not added.
- **Keys:** Up only when the editor has no row above the cursor (Down: none below), so a multi-line input keeps its arrows; the recalled
  entry comes with the cursor at its end.
- **The draft** typed before browsing comes back past the newest entry.
- **The edit rule:** once a recalled entry is edited, Down does nothing; the edited text becomes the draft, so Up then Down back past the
  newest brings it back. Unedited entries reached again by Up go on to newer ones as before.
- **A recalled command** keeps the command picker closed until it is changed, or the picker would take the next Up (found by a test).
- Tests: `PromptHistoryTests` (recall and draft, sent lines and commands, the edit rule, multi-line, the picker, dedup); mutations of the
  edit rule and the picker rule turn them red. Checked through the release binary in a PTY: Up, Up, Down, Down showed second, first, second,
  then the draft.

