---
status: in-progress
blocked-by: ["0046"]
date: 2026-10-20
---

# 0047 — Model registrations and aliases belong to one connection

A named connection can expose many server models and have several local registrations of one model with different
settings. Keep the live account catalog as observed data; store user aliases, defaults and overrides separately so a
refresh never erases the user's intent. This extends 0038, not a second source of provider implementations.

Proposed selection: `ask --provider work --model fast`, where `fast` resolves to a raw server id within `work` only.
An unregistered raw id remains usable explicitly; it is not replaced because a catalog omitted it. Aliases cannot point
to another connection, recurse, shadow a live raw id ambiguously or silently fall back to a different model.

Done when registrations persist per stable connection, survive rename/catalog refresh, resolve deterministically and
report both alias and resolved raw id. Multiple registrations of the same raw model are allowed, but names within a
connection are unique. Report a removed/unavailable model without deleting its registration. A provider capability
that a live catalog reports is not invented from an alias; distinguish verified server limits from user overrides.

The first settings are a default model and existing context/output limits; reasoning levels follow the catalog's actual
values and roadmap 0043. Do not introduce arbitrary provider-body overrides, embedded secrets or command execution.
Configuration precedence remains explicit flag → configuration → connection default → fresh catalog ordering. A
project file remains behind trust and cannot edit account registrations. JSON output, if added, exposes no secrets.

Probe stale catalogs, changed account identities, alias/raw-id collisions and migrated configuration before choosing
the final wire schema. Add create/list/update/remove CLI paths only after the underlying resolve/save behavior has
red/green tests. Session records keep the resolved raw id as well as the local label so a later alias edit cannot
retroactively change what a recorded request meant.

## Done (diary 39, ADR-0043)

Per-connection aliases and a default model: `ask connections alias|unalias|default`, shown by `ask models NAME`; resolved with the
server's id sent and recorded, the stated limits winning, nothing hidden, nothing chained, damage refused. Verified on the real
account and by `Scripts/probe-connections.py`.

## Still owed

- A reasoning level per alias (roadmap 0043, the thinking setting).
- Aliases for the default `codex` and `anthropic` connections, and a picker in the screen (the `/model` work on another branch).
- Whether a model that disappears from the account's catalog should be reported on use.

