---
status: accepted
date: 2026-10-28
---

# 0126 — Commands run in zsh, then bash, then the login shell, unless configured

## Context

The bash tool used `$SHELL`, else `/bin/bash`. A person whose login shell is fish got a model writing bash that ran in fish. The owner
(roadmap 0091, very high priority) wants a setting, and a default of zsh, then bash, then `$SHELL`.

## Decision

1. `environment.shell` names the shell: `zsh | bash | fish | sh | dash | ksh`, or an absolute path listed in `/etc/shells`. User file only.
2. Unset: the first `zsh` on the PATH, then the first `bash` on the PATH, then `$SHELL`, then `/bin/bash`. A configured name is looked up on
   the PATH first too.
3. The model's `shell` argument still overrides, under the existing rule (listed or the login shell).
4. `$SHELL` stops being first. The command's own `SHELL` variable is unchanged.

## Consequences

- Existing users whose login shell is neither zsh nor bash now get zsh. The tool description says which shell, each run.
- zsh differs from bash for some commands (an unmatched glob is an error). The model sees the shell name and writes for it.
- A configured shell that cannot be used falls back with a startup notice naming the shell used instead.
- zsh's description adds that an unmatched glob aborts the command.
