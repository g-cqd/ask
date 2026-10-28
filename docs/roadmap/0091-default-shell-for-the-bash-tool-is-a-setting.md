---
status: done
blocked-by: []
date: 2026-10-28
---

# 0091 — The default shell of the bash tool is a setting, zsh then bash then fish

Owner wish (`ask-wishes.md`, 2026-10-28 16:25, **very high priority**): a config option names the default shell for the bash tools.
Unset, it defaults to the first present of **zsh, bash, then `$SHELL`** (the owner corrected "fish" to "$SHELL" the same day).

## Today

`JobTable.commandShell` takes the model's `shell` argument when it is a listed login shell, else `$SHELL`, else `/bin/bash`
(`JobTable.swift`). `JobProcess` falls back to `/bin/bash`. Nothing looks for zsh or fish, and `$SHELL` can name a shell that is not
the one the person wants commands run in (a fish login shell makes the model write bash that runs in fish).

## Plan

- Setting `shell` (top level, a name `zsh | bash | fish` or an absolute path; validated against the same listed-shell rule as the tool's
  `shell` argument, so a config cannot name an arbitrary executable). The model's own `shell` argument still wins for one call.
- Default resolution: the configured shell if present, else the first of `/bin/zsh`, `/bin/bash`, `/opt/homebrew/bin/fish`, `/usr/bin/fish`,
  `/usr/local/bin/fish` that exists and is executable, else `/bin/sh` with a notice. `$SHELL` stops being the default: say so in an ADR,
  because it changes what existing users get (their login shell may have been fish).
- Check the tool description tells the model which shell it will get, so it writes the right syntax; check the sandbox profile allows
  executing whichever shell is chosen, and that fish quoting in `JobProcess` (`-c` versus login flags) holds.
- Tests: resolution order with fake presence, config beats default, a model's argument beats config, an invalid path is refused with a
  message, the description names the shell.

## Not decided

Whether `$SHELL` should still count when it names one of the three. The wish says presence order, so the plan ignores it.

## Result (2026-10-28, ADR-0126)

- Setting `environment.shell` (a name: zsh, bash, fish, sh, dash, ksh; or an absolute path the system lists in `/etc/shells`), **user file
  only** (a project file is refused). It sits in the `environment` section, which already reaches the tool, instead of a new top-level key.
- Default when unset: `/bin/zsh`, else `/bin/bash`, else `$SHELL`, else `/bin/bash`. The model's own `shell` argument still wins for a call.
- The tool description names the shell, so the model writes its syntax. Checked live on the release binary with the sandbox on:
  `echo $0` printed `/bin/zsh`, `$ZSH_VERSION` 5.9.
- A configured shell that is missing or unlisted falls back to the default silently (no notice channel in the tool): not ideal, open.
- Not verified: fish as a configured shell (quoting of `-c`, login flags in `JobProcess`); zsh-specific behaviour differences for commands the
  model wrote for bash (globbing that matches nothing is an error in zsh, `[[` and arrays differ in places); jobs' watchdog scripts keep `/bin/sh`.
