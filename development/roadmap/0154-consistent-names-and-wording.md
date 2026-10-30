---
status: done
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

## Owner's answer (2026-10-30)

"Everything presented is right, go ahead": all 40 rows of the table as proposed. Old names stay readable for a release, with a notice
naming the new one.

## Done (2026-10-30)

Every row as approved. Settings: `SettingRenames` reads each old name as its new one before decoding, keeps the key's place, refuses a
bad old value under the old name, lets a new name win over its old one, and the loader says each once at the start ("`ui.promptRows` is now
`ui.inputRows`; ask reads the old name for now"); `/config` reads the same way, so a save writes the new names. Switches are booleans
(`"on"`/`"off"` still read), `ask config` and the reload report print the new names (both now built from each section's key list), and
`docs/configuration.md` has an "Older names" table. `keepAwake` is `working`/`always`/`off` with `keepDisplayAwake` beside it, so "always,
display too" can be said (the power code takes the display separately). Flags: `--ask NAME` mirrors `--allow` (`--ask all` is the old
`--ask-always`, which is still read, hidden, with a notice), `--yes` says it is `--allow all`, and `--yolo` (0161). Commands: `/jobs`,
`/rewind`, `/config show`, `/model reset`; `/tasks`, `/tree`, `/config now` and `/model --reset` still work, and the picker finds a command
by its old name. Tests: `SettingRenamesTests`, `ApprovalAskWordsTests`, the configuration suites under the new names; probes updated (the
interactive probe, 282 checks, and 13 others pass).

Found on the way: the `/config` editor turned any text on a boolean row into `false` (`"maybe"` saved as `false`); it now checks the row's
choices first. Not done: row 31's prose pass beyond `--provider` and `/model`; the single `SettingDescriptor` list stays with 0118 and 0096.
