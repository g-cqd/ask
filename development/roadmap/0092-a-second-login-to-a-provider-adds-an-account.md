---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0092 — A second login to a provider adds an account instead of replacing the first

Owner wish (2026-10-28 16:25): logging in to a provider that is already signed in must not replace the previous account; it creates
another one. Models may be deduplicated in the list, but then the person selects which account serves them.

## Today

`/login` and `ask login` keep one credential per built-in provider, and named connections exist (`--name`, `--replace-account`). A login
without a name replaces the stored credential. The model list is per provider or connection name.

## Plan

- Investigate what exists first: named connections already hold several accounts per provider (ADR on connections); the wish may be
  mostly a default change (a login to an already-signed-in provider creates `provider-2`, or asks for a name) plus listing.
- `/model` shows a model once when several accounts serve it, then asks which account; `--model` with an ambiguous model names the
  accounts in its error and accepts `connection/model`. A setting for the default account per provider.
- Tests: second login keeps the first credential, both listed, ambiguous model needs a choice, explicit choice works, logout of one
  leaves the other.

## Not decided

Naming of the automatic accounts (by account email or id is better than `-2` but must never print a secret), and what `ask logout` does
with several accounts (it must name one).
