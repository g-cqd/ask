---
status: done
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

## Proposal for the two mixed keys (2026-10-31), for the owner

- `maxTurns`: a number, or `null` for no limit (`"none"` still read, and written back as `null` by the editor). `ASK_MAX_TURNS=none`
  stays, since an environment variable has no null.
- `compactAt`: split in two typed keys rather than one that is a number or a string: `compactAtShare` (a number from 1 to 100, the share
  of the window; default 75) and `compactAtTokens` (a number, or `0` for only when the window is full). Setting both is refused with
  the key named. `"75%"` and a bare number in `compactAt` stay read, with a notice naming the new key.
- Alternative kept smaller: keep `compactAt` as is, since `"75%"` reads well and is validated.

## Owner's decision and second step (2026-10-31)

Owner: "we should prefer null instead of none wherever we want to use such things. for compact at we could either specify a number of
token like 100000 or 0.95 for a share of it".

- `maxTurns: null` is no limit; `/config show` and the change lines say `null`. `"none"` is still read, as 0154 still reads
  `"on"`/`"off"`; `ASK_MAX_TURNS=none` stays, since a variable cannot be null.
- `compactAt` is one number: `0` only when the window is full, above 0 up to `1` a share in whole percents (`0.955` refused), above 1 a
  whole number of tokens. `--compact-at` and `ASK_COMPACT_AT` take the same numbers; `"75%"` is still read. The default shows as `0.75`.
- Kept as words: `sandbox.network`, `ui.queuedOnStop` and `approvals.remember` take `"none"` as one named choice among others, not an
  absence; `null` there would read as "unset, use the default", which is a different meaning.
- Tests: `TypedSettingsTests` (red first).

Still owed: the parser driven by the catalog, and `docs/configuration.md`'s tables generated from it.

## Third step: the catalog says what each key takes (2026-10-31)

- Each catalog row says what it takes (`SettingCatalog.Setting.expected`): from its kind (`true or false`, its words, `a whole number`,
  `a string`), or written out for a structured key. Every refusal now reads `"key" is <value>: use <expected>`, both for a string the
  key does not know and for a value of the wrong JSON type (`ConfigurationFile.refusal(of:in:path:)`, which shows the value from the
  file). Before, a wrong type showed the decoder's text (`DecodingError.typeMismatch: Expected value of type String`, for a switch),
  and a bad `maxTurns` or `ui.spinner` fell through to the sandbox scope's advice ("use workspace, anywhere or a list of paths").
- `docs/configuration.md`'s tables are held to the catalog by `SettingDocsTests` (keys, sections, defaults, "Your own file only")
  rather than generated: the docs' rows carry examples and caveats the catalog's one line of help does not, and are better written
  in Markdown. It found `skills.maxListed` and `skills.sources` documented as settable by a project although the parser refuses
  that, and two defaults worded differently.
- The decoding stays a switch per key: each key writes its own typed field, so a table would only move that code. The catalog drives
  the messages, the `/config` editor's rows and the example file, and tests hold the parser's keys, the example and the docs to it.

