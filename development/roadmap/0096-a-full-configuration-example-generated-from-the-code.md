---
status: done
blocked-by: []
date: 2026-10-28
---

# 0096 — A full configuration example, generated from the code

Owner wish (`ask-wishes.md`, 2026-10-28 16:46): the repository carries a complete example configuration file, generated from the code on
every build so that it never drifts. This may need a build plugin.

## Plan

- One source of truth: the keys the loader accepts (`ConfigurationFile` and each section's `keys`, the editor's known keys) with defaults and a
  one-line explanation each. Today that knowledge is spread over the decoders, `ConfigEditor+Validate` and `ConfigEditor+Settings`.
- Generate `docs/config.example.jsonc` (comments) from it; a test fails when the checked-in file differs, which is cheaper than a build plugin
  and runs in the gate. A build plugin only if the owner wants the file inside the product.
- Covers user-only keys (for example `environment.shell`) and says which a project file may set.

## Done (2026-10-30)

`SettingCatalog` lists every setting once (path, type, example, default in words, whether only your own file may set it, one line of
help); `docs/config.example.jsonc` is generated from it and checked by `SettingCatalogTests`, which fails when the file differs
(`ASK_WRITE_EXAMPLE=1 swift test --filter SettingCatalogTests` writes it). The example loads as a configuration file, sets every
top-level key, and uses no old name. A test, not a build plugin, as planned.
