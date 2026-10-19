---
status: not-started
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
