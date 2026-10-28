---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0115 — Take over another running session

Owner wish (2026-10-28 20:33). Pressing Left twice lists the sessions running elsewhere: a name and category for each (Apple Foundation
Models and its content tagging), what is happening there, and its path. Choosing one, from the selector or by a click, replaces the screen
with that session; nothing keeps running for the screen that was left, which simply quits its view. The session that was on screen goes on
in the background. When it waits for input or goes idle, it appears at the very bottom of the screen, below the jobs, after a blank row and
in a colour of its own; a click on it goes back to it.

## Still owed

- Investigate how other harnesses handle this (Claude Code, Codex, opencode, pi, Amp) and record it here.
- How sessions find each other: a registry under ask's state directory, liveness, and the sandbox rules for reading another session.
- What "take over" moves: the screen only, with the agent loop living in a process that is not the screen's (a daemon, or the session's
  own process kept alive headless).
- Naming with Foundation Models: on-device only, its cost against the 8 ms action budget (run it off the input path).
- The notification row and its colour, beside 0106 (purple) and 0107 (yellow).
