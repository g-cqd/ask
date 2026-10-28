---
status: done
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

## Result (2026-10-28, ADR-0125)

- Setting is `ui.onlyUsefulModels`, not `models.onlyUseful`. Parsers mark (`CatalogModel.unsuitable`), `ModelUsefulness` filters at read time.
- Applied to: `/model` rows, `ask models NAME` (`--all` shows the rest and a reason column; a line says how many were hidden), and the Codex
  default choice. Agy's default was already chosen among useful models. `--model` is always accepted.
- Hidden, from the recorded fixtures: Antigravity (live list; the 26-entry fixture is tested for the marks, not counted)
  (1 image generation, 2 tab completion, 2 not offered for chat); live Codex 2 hidden by the provider. Copilot's live list was not
  re-fetched; its marks are tested with synthetic entries only.
- No context floor was chosen.
- Not verified: OpenRouter's modality mark (the fixture has only `->text`, so only a synthetic body tests it); Anthropic and Apple mark nothing;
  caches predate the marks until refreshed; the Copilot and Antigravity marks come from the catalog's own flags, not from trying each model.
