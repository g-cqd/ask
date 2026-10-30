---
status: done
blocked-by: []
date: 2026-10-24
---

# 0064 — Keys: Esc never aborts, Ctrl+C clears the input, and stopping has its own key

The owner's direction (2026-10-24), from the lane-focus discussion: **Esc must not abort a turn**, **Ctrl+C must not kill ask directly and
erases the input**, and **there must be a key combination for killing a tool call, stopping a thinking or a sent request**, "ctrl+c or something
else but not esc". Today (ADR-0056, ADR-0040 and the README): Esc clears a selection, then aborts a running turn; Ctrl+C copies a selection, then
aborts a running turn, then quits when idle. This entry changes that, and the lane focus of 0062 depends on it, because **Esc has to mean
"go back" everywhere**.

**Built 2026-10-25 (ADR-0104, diary 2026-10-25 (17)):** Esc is inert in the editor, Ctrl+C is the ladder with the two-second quit window, the hints and README say so. **Not
built:** Esc returning focus from a lane (rules 3 and 4 below: there are no lanes until 0062), a dedicated stop chord, and stopping only a tool.

## The key model

**Esc is navigation only.** It never aborts, never quits, never clears a draft:

1. a selection is cleared (as now);
2. an open picker or list closes (as now);
3. a focused lane or the lane strip: focus returns **to the input**;
4. already in the input with main in view and nothing to close: if a lane other than main is the *focused lane* (the transcript shows it),
   focus goes back **to the main lane**;
5. otherwise nothing.

**Ctrl+C is a ladder, one step per press, never a kill on the first press:**

1. a selection: copy it and consume it (ADR-0056, unchanged);
2. the input holds text: **erase it** (the whole draft, as Ctrl-X does with nothing selected);
3. the input is empty and something is in flight (thinking, a request, a tool call): **stop it** (below);
4. the input is empty and ask is idle: the status line says `press Ctrl+C again to quit`, and a second press within two seconds quits.
   Anything typed in between disarms it.

So pressing Ctrl+C repeatedly escalates from "clear what I typed" to "stop what is running" to "leave", and a stray press never loses a session.

**Stop.** One chord stops whatever is in flight, whatever is in the input: **Ctrl+C with an empty input is step 3**, and for the case of text in
the input while a turn runs (steering text being composed) the user presses Ctrl+C twice, clearing then stopping. That is the whole proposal
for the chord; **if a dedicated chord that works with text present is wanted, it is not chosen here**, and the candidates are Ctrl+\ and a
Ctrl+letter not already used by the editor (Ctrl+A/B/D/E/F/H/J/K/U/W/X are taken). It must not be an Option or Command chord. What *stop*
does, by what is in flight:

- **thinking or a request in flight:** cancel the request; the turn ends and unsent queued messages return to the editor (as Esc does today);
- **a tool call running:** the tool's processes are stopped (SIGTERM to the group, then SIGKILL, as now) and **the turn is ended**, as an abort is
  today. *Killing only the tool and letting the model continue with an "interrupted" result* is a separate, finer action, not decided here;
- **a background job:** not stopped by this; it has its own `job_stop` and, with 0062, a row to act on.

**One input.** There is **one input slot**. It holds what is being written and sends to the **focused lane** (0062); a lane has no input of its own.
A click on the input returns focus to it from anywhere.

## Rules that must hold, each with a failing test first

- Esc with a running turn does nothing to the turn (it used to abort).
- Ctrl+C with text in the input erases it and does not stop or quit; with an empty input and a running turn it stops the turn; with an empty
  input and nothing running it arms the quit and a second press within two seconds quits, a key in between disarms it, and a first press never quits.
- With a selection Ctrl+C still copies and consumes it; a pending approval question keeps Ctrl+C as its "deny and abort" (ADR-0056).
- Esc returns from a focused lane to the input, and from the input to main when a lane is shown, and does nothing at main.
- Stopping leaves no process running (probed with real processes), and returns queued unsent messages to the editor.

## Probes

A real-PTY probe for each rung of the ladder and for Esc during a run against a fake provider and a real `sleep` tool call; the README, `/help`
and the status-line hints say the new keys.

## Done when

The rules have tests that failed before the change, the probe passes, and the old Esc-aborts behaviour is gone from the code, the README and
the help text, with an ADR that supersedes the key rules of ADR-0040 and ADR-0056 where they differ.

## Not decided

A dedicated stop chord that works with text in the input; whether to kill only a tool call; the quit-arming window (two seconds proposed).

## Superseded in part (2026-10-28)

The owner decided that Esc interrupts a running turn by default, with a second press as confirmation (a setting). "Esc never aborts" no longer holds; 0083 carries the survey and the settings. The rest of this entry stands until 0083 lands.

## Done (2026-10-30, close-out pass)

The key model is built (ADR-0104): Ctrl+C a ladder that clears, stops, then quits on a second press; a stop key; the help and README
say so. The owner then decided Esc stops a running turn by default, confirmed by a second press (0083, `ui.escapeInterruptRequiresConfirmation`),
which supersedes "Esc never aborts". "Not decided" stays undecided until someone needs it.
