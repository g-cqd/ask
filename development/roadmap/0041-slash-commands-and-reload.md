---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0034
---

# 0041 — Slash commands, and reload of ask's own binary

The last step of "developing ask from inside ask": the screen takes commands, and one of them replaces the
process with a rebuilt one, keeping the session.

## What landed

- **Slash commands.** `/help` and `/quit` are the screen's own and work while a turn runs. `/config`
  re-reads the configuration and shows every setting with its source. `/compact` summarises now. `/reload`
  switches to a new build. A path (`/etc/hosts …`) is still a prompt, and `//word` sends one that begins with
  a slash.
- **A seam, not a dependency.** `Conversation.commands`, `command(_:arguments:update:)` and `background(update:)`.
  A command is a run like a prompt: busy while it works, Esc aborts it, a second waits.
- **Reload** as in ADR-0034: identity, directory watch, self-check, close with a reason, close-on-exec sweep,
  `exec` with `--resume`.

## Evidence

- **Unit:** 17 slash tests, 6 identity, 5 watcher, 5 self-check, 4 screen-exit. The watcher and job suites ran
  60 of 60 repeated. 20 compiling mutations caught: 8 on slash commands, 3 on the self-check, 3 on the watcher,
  6 on the reload path (by the probes).
- **Probes in a real pty:** G (slash commands, including a real `/compact` after a pasted 90 KB prompt),
  H (replace the binary, reload, same session, cooked terminal after quit) and I (a broken build and a running
  job refuse; `/reload now` stops the job and reloads).
- **Live:** with the real model, a conversation survived a reload: same pid, session resumed, the code word
  recalled afterwards from a prompt re-sent and 90% cached. My first two live runs never reloaded (my script's
  wait matched my own prompt); the diary has it.
- **Cost:** none measurable on cold start or idle memory, after one fix (diary 24).

## Still owed

- **A build step in `/reload`** (run `swift build` from configuration, showing it) so one command rebuilds and
  switches. For now the agent builds with `bash`, then the user types `/reload`.
- **Automatic reload when idle**, only once the sandbox keeps the agent from writing the executable, or with
  a confirmation each time (ADR-0034, Security).
- **`/new`, `/resume`, `/model`** and the rest of interaction parity; **steering and multi-line input**.
- **Carrying the draft and scroll position** across a reload, which an automatic reload would need.
