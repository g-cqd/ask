---
status: not-started
blocked-by: []
date: 2026-11-08
---

# 0209 — One declaration per setting

From the rationalisation pass (research/rationalisation-2026-11.md §2.1; note n53, task t241). Adding `ui.dim` touched about eleven
places in four targets. Seven `*Preference` enums in AskAgentCore have twins in AskTUI, bridged by `rawValue` with a silent fallback.

## Decision first

The owner answered on 2026-11-08 (research note, §5.1): **AskTUI may depend on a leaf target of shared value types.** The ADR
records this and chooses the target, either AskCore or a new one, by what else would have to move with it. Each enum is then
declared once, and the screen's twins are deleted.

## The plan

1. **Red first.**
   - A test lists every `ui.*` key and fails where a key's enum and its screen twin differ in cases.
   - A test fails where `value(forKey:)` has no reading test (the mutation survivors of 2026-11-08).
2. **One descriptor per key.** Each key is described once: its type, its default, its documentation sentence, and its catalog row. From
   that one declaration come `keys`, `layered`, `value(forKey:)`, the decoding and the catalog. The descriptor is a value in a table,
   with no macros and no code generation step at build time.
3. **The bridge.** The mapping in `RunSettings+Screen.swift` becomes plain assignments, with no `rawValue`. The twin test from
   step 1 then has nothing left to check, and is deleted along with the twins.
4. **Migrate a section at a time**, starting with `ui` (the largest), with `docs/config.example.jsonc` regenerated and unchanged.

## Done when

Adding a `ui` setting with an enum value takes edits in at most three places: the descriptor, the screen option, and the docs
sentence, if that is not generated. A twin that drifts fails a test. The `@dl:accept` comments in `ConfigurationFile` and
`UISection` are gone or fewer than five.

## Not in scope

Changing any key's name or meaning; a new configuration format.
