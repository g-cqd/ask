---
status: not-started
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
