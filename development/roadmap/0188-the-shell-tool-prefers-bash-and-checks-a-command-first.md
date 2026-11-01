---
status: in-progress
blocked-by: []
date: 2026-11-01
---

# 0188 — The shell tool prefers bash, and checks a command before it runs it

Owner wish (2026-11-01 15:54): prefer bash (the one on `PATH`, then `/bin/bash`) to zsh, as models write bash by default. Check every
command the shell tool runs before running it: shellcheck or similar, or the shell's own checker where zsh or fish has one; the command
must work in the shell it will run in. Later, perhaps a shell parser and checker of ask's own, checking a command formally against the
system for safety.

Today (0091, done) the default is the first present of zsh, bash, then `$SHELL`, and a setting names another.

## Still owed

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
