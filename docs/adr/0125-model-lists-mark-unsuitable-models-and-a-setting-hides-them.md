---
status: accepted
date: 2026-10-28
---

# 0125 — Model lists mark the unsuitable models, and a setting hides them

## Context

Owner, 2026-10-28 (U19, roadmap 0089): a setting, on by default, that lists only the models useful for ask, for every provider. Each
provider's parser already dropped some entries, in its own way and silently, so turning that off was impossible.

## Decision

1. A catalog entry carries `unsuitable`, the reason it is of no use to ask's loop, or nil. Parsers keep the entry and set the reason: Antigravity
   (tab, image, audio, internal, not offered for chat), Copilot (not chat, disabled, no tool calls, no streaming, not in its picker), Codex
   (hidden, not in the API, no text input), OpenRouter-style lists (output without text).
2. `ModelUsefulness.shown(_:onlyUseful:)` is the one place that applies the setting, at read time, so the cache needs no refresh to follow it.
3. The setting is `ui.onlyUsefulModels` (on/off, default on), not the `models.onlyUseful` the roadmap proposed: a new config section
   was not worth one key.
4. A model with no mark is useful. There is no context floor: nothing recorded supports a number.
5. `--model` names any model whatever the setting says. `ask models NAME` says how many it hid and why; `--all` lists them.

## Consequences

- Caches written before this have no marks and list everything until refreshed with `ask models NAME`.
- Anthropic, Apple and plain OpenAI-style lists without modality data mark nothing; the filter is then a no-op there.
- A mark is only as good as what the catalog says; a model wrongly marked is reachable with `--model` or the setting off.
