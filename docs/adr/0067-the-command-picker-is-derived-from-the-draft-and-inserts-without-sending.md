---
status: accepted
date: 2026-10-23
---

# 0067 — The command picker is derived from the draft, and inserts without sending

## Context

Roadmap 0048 fixes what the two input sigils mean and how one picker serves both, and a throwaway prototype
(`docs/prototypes/ui-lab/lab.py`) pins the rules. Nothing of it was built. ADR-0044 and ADR-0046 decided that nothing
is painted, that no row starts with an icon or bar, and that every hidden thing leaves a placeholder. TerminalKit has no
picker mechanism: its `InputCompletion` only signals that the input thread has ended.

ask already has slash commands (`/help`, `/quit`, `/follow-up`, `/config`, `/compact`, `/reload`, `/new`, `/resume`,
`/model`), typed from memory and discoverable only through `/help`. This slice builds the `/` picker for them.

## Decision

1. **Derived, not modal.** After every key and paste, the picker is recomputed from the draft and the cursor, so it cannot
   disagree with the text. What it keeps is the choice (while the query is unchanged) and the first row of its window.
2. **A trigger is a sigil at the start of the word under the cursor** (`CompletionTrigger`). A `/` or `@` inside a word
   is text; `$` and everything else is never a trigger. The whole word is what accepting replaces; the query stops at the
   cursor. Offsets count characters, as the editor's cursor does.
3. **For commands, the word must also start the draft** (leading whitespace allowed) and be command-shaped (letters,
   digits, hyphens). That is where `SlashInput` makes a command run, so a command offered elsewhere would be inserted
   and never run, and `/etc/hosts` and `//config` stay prompts. The trigger is generic; this restriction belongs to the
   command source and is lifted when something that works mid-prompt (a skill, an `@` reference) is offered.
4. **Ranking:** a name that starts with the query, then a name that contains it, then a summary that mentions it, each in
   the order given; case-insensitive; empty query lists everything.
5. **Keys while it is open:** Up and Down move the choice and wrap; **Enter and Tab insert the choice, and never send**;
   Escape closes it and keeps the text, and it stays closed for that word until the cursor leaves it. Every other key is the
   editor's. Shift-Enter still inserts a newline.
6. **Two deliberate departures from the prototype's letter, for the owner to overrule:**
   - **A name typed in full closes the list**, so Enter runs it as it always has (`/quit` and Enter). With the list open on
     a full name, "Enter never sends" would make every command cost two Enters and break every script and habit. The rule
     still holds for anything left to insert.
   - **No picker on a screen under 12 rows.** A list nobody can see must not take Enter.
7. **Drawing:** a title row and up to seven matches (fewer on a short screen: `(rows - 6) / 2`), directly above the
   prompt, below the status line, taking rows from the transcript, which stays bottom-aligned and keeps at least a row. The
   title says what the list is, `N of M` when the matches do not all fit, and the keys, as many as the width allows. The
   chosen row is bold and in colour; nothing is filled, marked or started with an icon. An approval question hides it.
8. **The pointer:** the picker's rows are outside the transcript region, so a click there does nothing and the wheel
   scrolls the transcript as it does everywhere (the prototype's wheel rule, held by construction). Clicking a row is not
   built.

## Not decided here, and not built

`@` (files, agents, sessions), skills, a detail pane, clicking a row, and any change to where the trigger and ranking live.
Promoting the trigger and the ranking to TerminalKit is the right move once `@` is a second consumer; doing it first would
design a shared API from one use. Agent and session addressing need their own transport ADR (roadmap 0048).

## Probes

Unit tests of the trigger, ranking, controller and composer; a real-binary PTY probe (`Scripts/probe-picker.py`) with a
negative control against a binary that predates the picker. Mutation results and measurements are in the diary.
