---
status: in-progress
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

## Design entry (2026-10-31)

`development/research/session-takeover-2026-10-31.md` surveys Claude Code (agent view, a supervisor with a process per session,
`←` to background and attach), OpenCode (a server, `attach`), Codex (an app server, thread subscriptions), pi (RPC over JSONL) and Amp
(cross-client threads). It proposes a headless host process per session holding the loop, tools and jobs, with the screen as a client
over a Unix-domain socket. Sessions are found by their held locks plus a presence file, and a taken-over session moves only its
screen. No supervisor in the first version. Five phases, the first (listing what runs elsewhere, read only) useful without the split.

Waiting on the owner: two processes per session and the memory budgets; an unattached host's lifetime; what the screen that loses its
session does; no supervisor at first. The investigation and the registry, liveness, sandbox and "what moves" items above are answered
by the note; naming and the row's colour are proposed there.

## Owner (2026-10-31): one process, and three answers

- **No second process per session.** "Investigate various ways": the host-per-session design is set aside. Owed: a design that keeps
  one process per session, comparing the ways a screen can reach a loop in another `ask` process (the owning process serving its own
  session over a socket while it keeps its terminal; a hand-over through the session file with the loop restarted in the taker; others
  found), with what each costs in jobs, approvals and a turn in flight.
- **An unattached session's lifetime is the user's setting**, not a fixed hour.
- **The screen that loses its session stays,** with a notice and a way to take it back, perhaps switching to the list of sessions.
