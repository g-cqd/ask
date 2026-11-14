# What a command costs before its result is on screen (2026-11-14)

Asked by the owner after `measure-action.py`'s bash leg, repaired, read 97 ms where the records said 16 (diary 2026-11-14-06):
investigate, numbers first. Machine: mbp23, M2 Pro, macOS 27.2, Homebrew bash 5.3 and shellcheck on the `PATH`. Every figure is a
median; the command is `echo ok` (or `/usr/bin/true` under `sandbox-exec` alone).

## The first figure was the probe's, not a person's

The probes give ask an empty `HOME` so that commands never touch the real one. ask then protects two homes, the account's and
`$HOME`, and every home rule exists twice: 198 path rules instead of 102.

| Run | To the result on screen |
|---|---|
| The probe's environment (two homes) | 97.7 ms |
| `HOME` the account's, as a person runs it | 66.5 ms |
| ...with `--no-sandbox` | 49.0 ms |
| ...with `/bin/bash` and no shellcheck on the `PATH` | 29.8 ms |
| ...and `--no-sandbox` | 8.8 ms |

## Where 66 ms goes

| Part | Probe | Cost |
|---|---|---|
| ask's own work, one `/bin/bash` parse, the spawn | the last row above | 8.8 ms |
| shellcheck | `shellcheck --version` 21.4 ms; on `echo ok` 20.1 ms | 21 ms, all of it its start-up |
| Homebrew's bash, twice (the parse, then the run) | `bash -c :` 9.6 ms against `/bin/bash` 2.3 ms; it loads readline, ncurses and gettext from outside the shared cache | about 15 ms |
| The sandbox | sandboxed against `--no-sandbox`, both shells | 21 ms |

## The sandbox: the parameters, not the rules

`sandbox-exec` compiles the profile for every command. An empty profile is 8.5 ms. ask's profile names every path as a `-D`
parameter (`(param "DW7")`), so that no path can be read as profile text (ADR-0020).

| Profile | `sandbox-exec … /usr/bin/true` |
|---|---|
| empty | 8.4 ms |
| 200 parameters defined, none used | 8.3 ms |
| 50 / 100 / 200 / 400 parameters, each used once | 11.5 / 20.7 / 56.7 / 201.9 ms |
| 200 defined, 200 uses of the first | 9.4 ms |
| 200 defined, 200 uses of the last | 19.6 ms |
| 100 / 200 / 400 paths written as text | 11.9 / 21.3 / 58.1 ms |
| ask's, one home (102 paths): parameters / the same as text | 29.1 / 11.3 ms |
| ask's, two homes (198 paths): parameters / the same as text | 52.1 / 16.1 ms |

A parameter is found by a linear search, so n of them cost n squared; distinct paths have a smaller quadratic cost of their own.
In October "an empty profile costs the same as ours" (diary 2026-10-19 (25)) was true: there were few paths.

## Candidates, and what the owner chose

| | What | Measured | Chosen |
|---|---|---|---|
| A | A path of plain characters (ASCII letters, digits, `/._- +@,=:~`) written as text; any other stays a parameter | −11 ms a command (29.7 → 18.4 ms with `/bin/bash` alone); every sandbox suite under the real `sandbox-exec` stayed green, only the three tests of the profile's text failed. Probed: a hostile path spliced as text does add a rule; the allow-list keeps such a path a parameter; a mixed profile enforces both forms | **No** |
| D | shellcheck starts while the shell parses | −9.5 ms on a new command (65.4 → 55.8; 64.3 → 54.9 ms) | **Yes** |
| G | A command the check had nothing to say about is not checked again by the same tool | −33 ms on a repeated command (66.2 → 33.6 and 32.5 ms each, 60 in a row) | **Yes** |
| C | Compile the profile once and apply it per command (`sandbox_compile` / `sandbox_apply`) | not probed: private API, and a launcher between ask and the shell | not proposed |

A is not built: ADR-0020's "paths are parameters" stands, and its cost is now a known number (about 18 ms a command for one
home) rather than an unknown one. Should it be wanted later, the prototype was 11 lines in `SeatbeltProfile`.

## After D and G (as landed)

A person's `echo ok`: 55 ms the first time, 33 ms when repeated (from 66 ms each). What is left of the 33: 9 ms ask and the spawn,
8 ms Homebrew's bash once, about 18 ms the sandbox.

## Not measured

Another Mac, or a `PATH` whose bash is the system's (the Homebrew share is this machine's). Commands longer than 4 KiB, which G
does not remember. The cost of a shellcheck run that a parse failure makes useless (D starts it anyway; it is one 21 ms process).
