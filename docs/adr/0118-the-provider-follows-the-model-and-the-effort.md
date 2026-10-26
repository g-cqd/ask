---
status: accepted
date: 2026-10-26
---

# 0118 — The provider follows the model and the effort

## Context

`--model gpt-6-sol` sent the model to whatever provider was in force, so naming a model meant naming its provider too, and `/model MODEL` kept the current provider and failed on a model it did not serve.

## Decision

1. A model may be written `provider/model` (`--model`, `/model`, `config.json`'s `model`). Only the part before the **first** slash, and only when it names a provider that exists (a built-in, a key preset, a configured
   provider, a stored key, a named connection; `claude` means Anthropic), qualifies. A router's `org/model` is left whole, and `openrouter/org/model` is that provider's `org/model`.
2. A model written without a provider is looked for in the **cached** list of every account signed in to (never a network at launch), and the provider that holds it serves it. Several: the one that takes the
   thinking effort asked for, then the order Claude, Codex, Antigravity, keys. None: the provider in force, as before. The choice is announced once (`gpt-6-astra is served by codex; codex/gpt-6-astra says so.`).
3. Never overridden: a provider named with `--provider` or by `/model PROVIDER MODEL` (a prefix equal to it is only dropped; a different one is left in the model id), and a model the configuration file chose.
4. With no model at all, the default provider order already prefers the accounts that take an effort over Antigravity and the on-device model, which take none.

## Evidence

- Real binary, Codex signed in, nothing else: `--model gpt-6-astra`, `--model codex/gpt-6-sol`, `--model apple/on-device`, `--model on-device` each answered `OK` on the provider the model belongs to;
  `--model gpt-6-sol --thinking high` chose Codex and sent effort `high`.
- `ReferencedModelTests` (5): bare, qualified, a router's slash, case and `claude`, nothing after the slash.

Not done: inference reads cached lists only, so a model of an account that has never listed its models is not found (it stays on the provider in force, and `/model` lists it); there is no test of the inference itself,
which lives in the executable (`ModelQualifier`) where nothing is tested yet.
