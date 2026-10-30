---
status: in-progress
blocked-by: []
date: 2026-10-30
---

# 0154 — Consistent names and wording for settings, flags and commands

Owner wish (2026-10-30), to come early: refine the naming and wording of configuration settings and commands across ask so they are
consistent and aligned.

## What to review

- **Settings:** case and shape of keys (`ui.localizedDurations`, `ui.jobAutoReturnWhenFocused`, `ui.abortTurnRequiresConfirmation`,
  `ui.escapeInterruptRequiresConfirmation` beside `ui.timeout`, `keepAwake`, `credentials`), on/off strings against booleans (0118),
  choice vocabularies (`folded`/`open`, `open`/`closed`, `on`/`off`, `auto`/`always`/`never`), and where a setting lives (`ui` against
  top level, `sandbox` against `approvals`).
- **Flags:** `--yes` and `--ask-always` beside `--no-sandbox`, `--network`, `--write`, `--read`, `--allow`; one verb per idea.
- **Commands:** `/tasks`, `/tree`, `/fork`, `/reload`, `/model`, `/config`, `/mcp`, `/compact`, `/new`, `/resume`: names, arguments and
  the sentences they print.
- **Messages:** the same thing said the same way everywhere (allowed, denied, refused, not permitted; "this time" against "once").

## How

A table of every name as it is and as proposed, with the reason, for the owner to accept row by row; then renames with the old names
still read (a notice says the new one) for a release, tests for both spellings, and the docs and `ask config` updated together.

## The table (2026-10-30)

`development/research/naming-table-2026-10-30.md`: five conventions (switches as booleans, keys name what you see, one word per idea,
flags mirror settings, bare-word command arguments) and 39 numbered rows over every setting, flag, environment variable, slash command
and the recurring messages; 24 propose a change, the rest are listed as staying. Waiting on the owner's answer row by row. Found while
making it: the `/config` editor lists no `approvals` row, and its list, the parser and the docs table are three hand-kept copies, which the
`SettingDescriptor` list (with 0118 and 0096) replaces once the names are settled.

