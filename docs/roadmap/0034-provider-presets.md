---
status: in-progress
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0034 — Built-in presets for the OpenAI-compatible providers

`--provider groq` should work with `GROQ_API_KEY` set and no `providers.json`. The twelve base URLs and key variables
in `docs/research/provider-connections-2026-10.md` were each probed on 2026-10-19 (401 with an auth error, or a
public model list), so presets carry only verified endpoints. A `providers.json` entry of the same name overrides a
preset, and a preset with its variable unset is listed as unavailable, never sent without a key.

Done when each preset resolves from its variable, `ask --provider NAME` lists what is available when NAME is not,
and the context windows of known models are filled in where the provider's catalog reports them.

## Done (diary 18)

Twenty-four presets from pi's catalogue, each resolving from its key variable with no `providers.json`; an entry of the
same name overrides only what it gives; an unknown name lists the presets and which still need their variable.

## Still owed

- Context windows of known models, from each provider's catalog.
- `opencode` and `opencode-go`, which need an `x-opencode-session` header per conversation.
- `ant-ling`, whose endpoint answers only HTML to unauthenticated requests.
