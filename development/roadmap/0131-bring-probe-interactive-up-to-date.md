---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0131 — Bring probe-interactive.py up to date

Owner request (2026-10-29): drop the `ask> ` expectation from `Scripts/probe-interactive.py`.

## Done

The prompt, the "ready" word and the "working" word are no longer read from the screen. `Screen.idle()` is the status line leading with its
`!` mark (a turn shows a spinner there), `Screen.editor_lines()` is what sits between the last two rules, and `until_status("ready")`,
`until_status("X · ready")` and `until_status("working")` keep their calls and mean those things.

## Still owed

The probe takes minutes and many of its checks are older than 0074, 0064, 0080 and the folded-by-default tool blocks, so they fail for
other reasons than the prompt: a tool call is shown folded now, `/config` and the reload messages were reworded, resumed sessions say
less. The full list of failing checks is in the diary. Fix them group by group, each against what the screen is supposed to do now,
not by loosening the check; split the file (1,300 lines) into one probe per scenario while at it, so a scenario runs alone in seconds.

## The failing checks after the prompt change (2026-10-29, release build)

155 checks pass and 49 fail, in 19 of the 25 scenarios:

- A: a turn on screen (1): tool call shown, succeeded
- B: Ctrl-C stops a running command, and Esc does not (1): tool shown as stopped
- D: --continue shows the earlier conversation and carries it on (3): says which session it resumed; earlier tool call shown, succeeded; usage so far on the status line
- F: configuration edited while ask runs is reloaded before the next prompt (3): the change is announced; with each setting and where it came from; a fixed file reloads again, from the settings that were in force
- G: slash commands (12): and the conversation's; /config shows each setting with its source; and the files; /config reads the files again and announces the change; and shows the new value from its file; a path is a prompt for the model; /compact with only a short exchange says nothing could be summarised; a large prompt is answered; /compact summarises the older conversation; through one summary request; and the next prompt carries the summary; /quit leaves cleanly
- H: /reload switches to a newly built ask and keeps the session (3): a new build appearing beside the running one is announced; and the new process says it reloaded; resuming the same session
- H2: /reload checks a new build with the key the provider reads from the en (2): a new build is announced; the reload goes ahead
- I: a broken build, and running jobs, stop a reload (2): with a good build, /reload now reloads; into the same session
- K: stopping returns unsent input to the editor, without persisting or run (5): Esc with a draft typed does not end the run; the first Ctrl-C erases the draft; the editor holds both unsent messages on separate lines; nothing was automatically requested after abort; unsent messages never entered the session
- M: a multi-line prompt: pasted, typed, edited by line, submitted whole (1): the transcript shows the prompt on four rows
- N: /new releases the old session and starts the next one lazily, with no  (1): only new usage is shown
- P: /resume lists and switches sessions transactionally; refusal preserves (1): an empty list is reported without creating a session
- Q: /model is run-local, atomic, pinned to its provider, and survives relo (1): the current model is reported without a request
- R: the status line says when the sandbox is strict, or off (4): --write workspace --network none; --network localhost; --read workspace; --no-sandbox
- S: /resume adopts a session's recorded sandbox and /new drops it (2): resuming adopts the recorded sandbox; and says so
- T: in a resumed session /model overrides the recorded destination; /resum (2): /model overrides the recorded destination, as the user's consent; /resume goes back to that session's own model, dropping this run's choice
- V: a call asking for more than the sandbox allows is put to the user: onc (2): a larger request asks; n refuses it, saying who can widen the sandbox
- Y: undoing the session's narrowing asks; /model keeps it and /new drops i (2): /model rebuilds the loop without losing the narrowing; /new drops the narrowing
- Z: a remembered write grant is not permission to undo a network narrowing (1): no keeps the narrowing

## Progress (2026-10-29)

`probe-lines-below.py` repaired (the status line is the last row with text; idle is the mark) and `probe-picker.py`'s startup wait accepts
the mark, so every probe built on `pp.Session` starts. `probe-lines-below` passes 5 of 5 against the release binary. `probe-picker`,
`probe-tree`, `probe-files` and `probe-picker-click` start now but still fail further in on other expectations of the old layout;
`probe-pointer` fails 19 checks, `probe-input` fails at startup. Still open.
