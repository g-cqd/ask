---
status: done
blocked-by: []
date: 2026-10-28
---

# 0098 — No turn limit by default, except in the sandbox

Owner wish (2026-10-28 16:51): remove the default `maxTurns` limit (100 today, `Configuration.swift`); enable it when the sandbox is on; always
respect the person's configuration.

## Open point

As written, "enable it when in sandbox" keeps the limit for the default run, since the sandbox is on by default; read literally the limit
applies only when the sandbox is on and is gone with `--no-sandbox`. Confirm with the owner whether the intent is the reverse (no limit while
sandboxed, because the sandbox already contains the risk). Until confirmed, implement: an explicit `maxTurns` always wins; unset means a limit
with the sandbox on and none without.

## Done (2026-10-28)

- The owner asked for the limit to be removed, in their config at least. `maxTurns` now takes `"none"` in a config file and
  `ASK_MAX_TURNS=none`, kept as `Configuration.noTurnLimit` (`Int.max`, a count the loop never reaches); `ask config` and reload notices
  show `none`. A loop test runs 151 requests with no limit and ends when the model stops.
- The owner's `~/.config/ask/config.json` was created with only `"maxTurns": "none"`; `ask config` reports it as applied.
- The `--max-turns` flag still takes a number only.

## Owner's rule (2026-10-28 20:40)

"defaults to 100 when in sandbox, defaults to none when no sandbox, either way, if a setting is set, use it." This settles the open point.
`Configuration.turnLimit(sandboxed:)` holds the rule: a `maxTurns` from any layer (file, environment, flag) wins, even `100` written out;
unset, it is 100 with the sandbox on and no limit with `--no-sandbox`. `ask config` shows the effective value and, for the default, which
case applies. Tested in `ConfigurationChangesTests`.
