---
status: not-started
blocked-by: []
date: 2026-11-08
---

# 0210 — One registry of slash commands, with typed handlers

From the rationalisation pass (research/rationalisation-2026-11.md §2.2; note n53, task t241).

## Today

- Commands are declared in two tables: `ScreenController.builtIn` in AskTUI and the conversation's table in ask.
- They are dispatched by a `switch` on the name in two places: `ScreenController+Submit` (12 cases) and
  `AgentConversation+Commands` (20 cases).
- `thread`, `rename`, `merge`/`close` and `reload` are matched in both, and `reload` is forwarded by its name as a string.
- A name with no handler, or a handler with no name, is found only by typing it.

## The plan

1. **Red first.** A test enumerates every listed command and fails where one has no handler, where a handler has no listed name,
   or where a name is matched in both layers without saying which one owns it.
2. **One registry value per command:** its name and aliases, its summary, its category, where it runs (on the screen, or in the
   conversation), and a handler typed by that place. The screen's registry and the conversation's are joined once, at launch.
   The picker, `/help` and dispatch all read the joined list.
3. **No dispatch by string.** A thread lane's override is a registry entry with a scope, not a second `switch`.
4. **The tables lose their suppressions.** Entries built by one initialiser are data. If the duplicate detector still reports them,
   it learns to skip one initialiser's array literal (a dolly option), not each entry.

## Done when

There is one list of commands. Both `switch` statements on command names are gone. The test from step 1 guards the joins. `/help` and
the picker show the same list as before; a PTY probe compares the picker before and after.

## Not in scope

New commands; renaming any command.
