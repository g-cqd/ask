---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0025
---

# 0029 — Resume a session

Long work needs to survive closing ask, and reloading ask's own binary will re-exec with a resume.

## What landed

- **Commands.**
  - `-c`/`--continue` takes the session written last in this project. With none, it starts a new one and says so.
  - `-r`/`--resume <name|prefix|path>` takes a named session.
  - `ask sessions` lists sessions newest first, with each one's first prompt.
- **Both modes.** `-p` appends to the resumed session. The screen replays the conversation and the usage so
  far before the prompt.
- **One writer per session** (ADR-0025). A second `ask` is refused with exit 75, and nothing is written.
- **Crash tails need no special path.** `RequestContext` answers a call that was never answered as
  interrupted, and the replay shows it that way.

## Evidence

- **Fake-server probes** (`Scripts/probe-agent-run.py` C and D, `Scripts/probe-interactive.py` D):
  - re-sending of the earlier exchange;
  - refusal while a Python process holds the lock, with the file left byte-identical;
  - lookup by name prefix;
  - continuing after a SIGKILL mid-command;
  - the screen redrawing a resumed session.
- **Live.** A word given in one `-p` run was recalled by `-p --continue`, and the resumed run read 97% of its
  prompt from cache.

## Left for later

- A picker and `/resume` in the screen; slash commands come with interaction parity.
- Resuming a different branch of the session tree.
