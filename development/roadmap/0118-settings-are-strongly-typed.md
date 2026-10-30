---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0118 — Settings use strong, simple types

Owner wish (2026-10-28 20:33): enforce configuration settings with strong and simple types instead of free or non-standard text. Flags are
booleans (on or off), which may mean rewording some settings; investigate the others to enforce types further.

## Still owed

- Inventory every key with its type today: booleans written as `"on"`/`"off"` (0102 made both forms work), enums as strings, numbers,
  and mixed ones such as `compactAt` (number or `"75%"`) and `maxTurns` (number or `"none"`, roadmap 0098).
- For each mixed or textual key, propose a typed form, for example `"maxTurns": null` for no limit, or a separate boolean.
- Decide with the owner whether `"on"`/`"off"` stays accepted, and how old files migrate.
- Validation that points at the key and says the expected type, already the pattern in `ConfigurationFile`.

## First step (2026-10-30)

Switches are booleans (0154). The catalog (0096) is now the list of every key with its type, held to the parser's keys by a test, and the
`/config` editor's rows come from it (the `ui` section first, as before), so a new key is missed in one place less. Still owed: the
parser itself driven by the catalog, typed forms for the mixed keys (`maxTurns` as a number or `"none"`, `compactAt` as a number or a
share), and `docs/configuration.md`'s tables from the catalog.
