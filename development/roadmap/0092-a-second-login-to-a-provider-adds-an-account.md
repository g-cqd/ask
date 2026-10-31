---
status: done
blocked-by: []
date: 2026-10-28
---

# 0092 — A second login to a provider adds an account instead of replacing the first

Owner wish (2026-10-28 16:25): logging in to a provider that is already signed in must not replace the previous account; it creates
another one. Models may be deduplicated in the list, but then the person selects which account serves them. The default chosen for
several accounts of one model (`development/research/priorities-2026-10-31.md`): ask once, remember per model, change with `/model`.

## Before

A Claude or Codex sign-in without `--name` replaced the stored account. Named connections held other accounts only when the person
named them first, and `/model` listed a model once per account.

## Now

- A sign-in without a name (`ask login` and `/login`, one code path) goes to the default when the default is empty or holds the same
  account (a Claude address compared without case). It goes to the connection that already holds the account, if any. Otherwise it
  becomes a new connection: `claude-<local part of the address>` (characters other than letters, digits, `.`, `_`, `-` become `-`), or
  `codex-2`, `codex-3`… since a Codex account id means nothing to a person; `-2`… on a name in use, and never a configured name. An
  account whose identity the provider did not give never replaces a signed-in default. The sign-in's line says where it went and how to
  rename it or replace the default instead (`ConnectionRegistry.placement`, `storeSignIn`).
- `--replace-account` without `--name` now replaces the default's account; it used to be refused.
- `/model` groups a model the accounts of one subscription serve (`ModelOfferGroup`): one row naming its accounts. Never chosen, the row
  writes the model in the draft and the picker then lists its accounts (`ChoiceRow.revealedBy`, a row listed only once the typed text
  starts with its prefix). Chosen with an account, the account is remembered for that model in `model-accounts.json` beside the
  configuration (`ModelAccountMemory`), the row then runs with it, and `/model MODEL` typed by hand uses it. Typing a space after the
  model lists the accounts again, which is how the choice is changed.
- Keyed providers are never grouped: the same id at two services is not the same model.

## Tests

- `SignInPlacementTests` (8) and `SignInStoreTests` (3): default when empty or same account, case-insensitive addresses, a new
  connection kept beside the default with its name, name collisions, a connection taking its account back, replacing, an unknown identity.
- `ModelOfferGroupTests` (4), `ModelAccountMemoryTests` (3), `ChoicePickerAccountTests` (3, the picker in the screen's state machine).
- `Scripts/probe-model-accounts.py`: the release binary in a PTY, with synthetic Codex credentials and cached lists for the default and a
  `codex-2` connection. One row, accounts revealed on choosing, the account selected, remembered, and offered next time (8 checks).

## Decided differently from the plan

- `--model` with a model several accounts serve is not an error: it uses the default's account, as before, so no script breaks. Name
  the account with `--provider`. `/model MODEL` uses the remembered account.
- No separate setting for a default account per provider: the default sign-in is that, and `--replace-account` changes it.

## Not verified

- A real second-account browser sign-in for Claude or Codex: the placement is tested on the store, not against the providers.
- The probe was not run against a binary from before the change, to see it fail.
