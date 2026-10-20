---
status: in-progress
blocked-by: []
date: 2026-10-19
decision: ADR-0031
---

# 0038 — Model catalogs, so a signed-in provider needs no `--model`

After `ask login spettro`, `ask --provider spettro` still says it lists no model. Spettro's `/v1/models` reports
`context_window`, `vision` and `reasoning` per model; OpenAI-compatible services generally list `/v1/models` too. Read the
catalog with the stored key, cache it beside the credentials, choose a default, and fill `contextWindow` from it, which
ADR-0030 already uses. Probe each preset's list endpoint first: OpenRouter and Hugging Face answered it without a key
(diary 16); the rest need one.

## Done (diary 28, ADR-0037)

Codex only: the account's live catalog (`ask models codex`), an account-scoped cache, and a default chosen from it when no
model is named. Observed on one real account.

## Done (diary 45)

Codex reasoning levels: each model's levels and default as the account reports them, kept in the catalog cache, shown by
`ask models`. None of the nine models offers an "off". Setting a level is roadmap 0043's.

## Still owed

- Spettro and every preset with a list endpoint, each probed with its own key first.
- Per-connection registrations and aliases (0047).
