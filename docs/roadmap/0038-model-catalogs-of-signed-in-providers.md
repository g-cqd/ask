---
status: not-started
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

Codex has no default model today (ADR-0036): `--model` is required. Its catalogue is `GET /backend-api/codex/models`,
which pi-integrations reads from strings in the Codex CLI and has not seen answer; probe it with a real token first.
