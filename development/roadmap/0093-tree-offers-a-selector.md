---
status: done
blocked-by: []
date: 2026-10-28
---

# 0093 — `/tree` offers a selector, not only an argument

Owner wish (2026-10-28 16:25). `/tree` lists prompts, and going back needs `/tree N`. It should open a selector like `/model` and
`/resume` do.

## Plan

1. A picker (the existing `ChoiceRow` list used by `choices(for:)` in `AgentConversation+Choices.swift`) of the session's user turns,
   each choice running `/tree N`. This is the whole of the first step.
2. Less of a priority: draw the picker as a tree (branches from earlier rewinds, indentation by depth).
3. Less of a priority: list model and tool turns as well as user turns, so a session can restart between any two turns. That needs
   `SessionOutline` to expose every turn and the rewind to keep tool-call and result pairs together (never cut between a call and its
   result; the same rule compaction follows).

Tests: the rows match `SessionOutline`, choosing one equals the typed argument, an empty session offers none.

## Result (2026-10-28)

Step 1 only, as the plan said. `/tree` is a command that takes choices: with no argument it opens the picker `/model` and `/resume` use,
one row per prompt, newest first, `N  first line of the prompt · branch after M`, the prompts on the path you are on marked as current.
Choosing a row is `/tree N`, which goes back as before and puts the prompt in the editor; `/tree N` typed still works. The rows come from
`SessionOutline.picks()` (tested), the screen's picker is the generic one. Real binary: `Scripts/probe-tree-picker.py`. The old
notice listing is no longer reachable from the screen. Not done, as listed: drawing the picker as a tree, and listing model and tool turns.

