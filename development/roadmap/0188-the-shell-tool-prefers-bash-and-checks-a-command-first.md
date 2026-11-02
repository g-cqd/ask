---
status: done
blocked-by: []
date: 2026-11-01
---

# 0188 — The shell tool prefers bash, and checks a command before it runs it

Owner wish (2026-11-01 15:54): prefer bash (the one on `PATH`, then `/bin/bash`) to zsh, as models write bash by default. Check every
command the shell tool runs before running it: shellcheck or similar, or the shell's own checker where zsh or fish has one; the command
must work in the shell it will run in. Later, perhaps a shell parser and checker of ask's own, checking a command formally against the
system for safety.

Today (0091, done) the default is the first present of zsh, bash, then `$SHELL`, and a setting names another.

## The plan, as first written (the outcome follows)

- The default order becomes bash on `PATH`, `/bin/bash`, then zsh, then `$SHELL`; the setting still wins. macOS's `/bin/bash` is 3.2:
  say which bash ran in the tool's description, so the model does not write bash 4 features for bash 3.2.
- Before a command runs: a syntax check by the shell that will run it (`bash -n`, `zsh -n`, `fish --no-execute`), and shellcheck when it is
  installed and the shell is bash or sh, with its findings given back to the model; a syntax error stops the command, a shellcheck warning
  does not. Measure what each costs per command.
- Later, separately: a parser of ask's own (the protections already read commands: `StandardProtections`), which could check a command
  against the sandbox's rules before it runs.

## Done (2026-11-01)

ADR-0139: bash on the PATH, `/bin/bash`, zsh, `$SHELL`; `/bin/bash` named as 3.2 in the tool's description; every command parsed by its
shell before it runs (not run when it does not parse); shellcheck's findings with a failed bash or sh command's result. Still owed: the
parser of ask's own (the item's last point).

## Changed (2026-11-02)

The owner found that shellcheck's findings did not stop a command, so the model waited on a flawed one, and asked for a new default order.
His choices:

- Findings refuse once: a command with shellcheck findings of warning or error level is not run, and the findings come back at once.
  Sending the same command again (same shell) runs it as written, once (`RefusedCommands`, the last 16 kept).
- The check keeps its 3 s deadline; a command whose parse or shellcheck runs past it still runs, and its result ends with
  "[not checked: …]" (`CommandCheck.Result.unchecked`).
- The default shell: bash on the PATH, `/bin/bash`, then a POSIX shell, closest to bash first (ksh, sh, dash), on the PATH, then in `/bin`
  and `/usr/bin`; then `$SHELL`; `/bin/sh` when nothing is found (`JobTable.defaultShell`). zsh is no longer a default of its own. Not
  answered: whether a shell earlier on the PATH beats a preferred name; each name is looked for over the whole PATH in turn.

- Not every warning refuses (the owner's choice, after the suite showed valid commands refused): SC2154 (a variable from the environment),
  SC2034 (one a child or a later command reads) and SC1010 (`done` as a word) cannot be judged in a single command. They are still told
  with a failed result (`CommandCheck.refuses`).

Found on the way: the check's deadline was a task on the cooperative pool, whose thread the check blocks while reading, so under load it
never fired and the command waited on its check. It is now a thread of its own (`CheckWatchdog`) sleeping in `poll` on a pipe, which the check closes when it
ends, so a quick check leaves nothing waiting.

Mutation testing of this change is owed (t190).

## Left

The parser of ask's own is later work, outside this item: it checks commands against the sandbox's rules, which 0188 did not set out
to do.
