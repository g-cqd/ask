---
status: not-started
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
