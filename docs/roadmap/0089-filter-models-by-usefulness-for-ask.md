---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0089 — A setting that lists only the models that are useful for ask

Owner, 2026-10-28 (on Antigravity's `tab_*` and image models, applied to **all providers**): propose an ask-wide config setting that
filters each provider's models by actual usefulness for ask. **On by default.** When off, every model of every provider is allowed.

## Proposal

- Setting `models.onlyUseful`, boolean, default `true`, validated in the config editor, documented in `ask config`.
- "Useful for ask" is a property of the model's catalogue entry, decided by one function in one place (not per provider):
  a model is useful when it (1) takes text input and gives text output, (2) supports tool calls, and (3) has a context window large
  enough for ask's loop (a floor to be chosen with a measurement; 0069's registry has the figures). It is *not* useful when it is an
  embedding, image-generation, speech, moderation, code-completion ("tab") or realtime-only model.
- Where a provider's list does not say (no tool-call flag), the filter keeps the model and marks it "unverified", rather than
  hiding something that works. The decision is visible: `ask models <provider>` shows what was hidden and why when asked
  (`--all`), so the filter never silently removes a model.
- Applies to the model picker, `ask models`, `/model` completion and the default choice. When off, all of them list everything. A
  model named explicitly with `--model` is accepted whatever the setting says, if the provider serves it.
- Antigravity: `tab_*` and the image models fall out under (1) and (3); this is recorded as the answer to 0069's U19.

## Work

1. A `ModelUsefulness` value computed from the catalogue entry, with a table test per provider's recorded list (a fixture of each).
2. The setting, wired to every list path; tests with it on and off.
3. A diary entry with the counts hidden per provider.

## Not decided

The context floor, and whether "tab" models of providers other than Antigravity exist in practice. Both come from the fixtures.
