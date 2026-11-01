---
status: accepted
supersedes: ADR-0126
date: 2026-11-01
---

# 0139 — Commands run in bash first, and are parsed by their shell before they run

## Context

ADR-0126 chose zsh, then bash, then the login shell, for the shell tool's commands. The owner (2026-11-01, roadmap 0188) asked for
bash first, the one on the PATH then `/bin/bash`, since models write bash; and for every command to be checked before it runs, by
shellcheck or the shell's own checker, so that it works in the shell it will run in.

## Decision

- **The default order**: the first bash on the PATH (Homebrew's bash 5 on most Macs), `/bin/bash`, the first zsh on the PATH, then
  `$SHELL`. `environment.shell` and the model's `shell` argument still win. When the shell is macOS's `/bin/bash`, the tool's
  description says it is 3.2 and what it lacks (associative arrays, `mapfile`, `${var,,}`, `|&`).
- **Every command is parsed first**, by the shell that will run it, with nothing run: `-n` (zsh with `-f`, fish with `--no-config
  --no-execute`), in an environment of the PATH alone, so no `BASH_ENV`, `ENV` or `ZDOTDIR` is sourced. A command that does not
  parse is not run; the tool returns the shell's message. 2 to 8 ms a command (M3).
- **shellcheck** reads a bash or sh command when it is on the PATH (`--norc`, warnings and errors, about 23 ms). Its findings come
  back with the result of a command that failed, where they may say why, and not with one that succeeded, where they would be noise
  the model pays for. They never stop a command: shellcheck has false positives, and it does not know zsh or fish.
- A check that cannot start, or takes more than 3 s, lets the command run as it would have.

## Consequences

- Commands that relied on zsh's behaviour by default (an unmatched glob aborting) now run in bash; a person who prefers zsh sets
  `environment.shell`.
- A parser of ask's own, checking a command against the sandbox's rules before it runs, stays a later step (roadmap 0188).

## Evidence

6 tests for the check, the shell-order suites rewritten for the new order (red first: 11 failures before the change). Mutations: a
command that does not parse being run, findings on every result, the parent environment passed on, zsh reading its startup files,
shellcheck reading an rc file, and the shell checking nothing each turn the tests red. Running shellcheck for zsh too survives: an
equivalent mutant, as shellcheck refuses a zsh dialect and says nothing; the guard only spares a process.
