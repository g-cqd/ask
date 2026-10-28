---
status: accepted
date: 2026-10-20
---

# 0042 — A model chosen in the screen is a run-local layer above the configuration

## Context

Choosing a model needed a file edit or a flag and a restart. Configuration already has layers, provenance and
an all-or-nothing reload (ADR-0032), and `/reload` replaces the process (ADR-0034), so a choice made in the screen
has to fit those, not bypass them.

A model id means nothing without the provider that serves it, and ids contain slashes and colons
(`vendor/model:tag`), so neither can be guessed from the other.

## Decision

- `/model` shows the current model and where it came from. `/model MODEL` chooses a model on the provider in
  force now. `/model PROVIDER MODEL` chooses both. `/model --reset` goes back to what the configuration says.
  Words are split on spaces only; a lone word is a model id, never a provider.
- A choice is the top layer: above files, `ASK_*` variables and flags. It replaces **provider and model together**
  and names its source `/model (this run)`, which `/config` and the reload notice show. It is never written to a file.
- The provider is pinned when the model is chosen. A later edit of `config.json` still reloads (maxTurns,
  sandbox and the rest), but cannot swap the provider under a model chosen for the old one.
- A choice is adopted only if the whole configuration, with it, resolves with no network: unknown provider, a
  provider with no key, a refused endpoint or an unusable file all leave the current model in force and say why.
  Resolution is the check. Whether the account may use that model is learnt by the request, as with `--model`.
- A choice survives `/reload`: the replacement process is started with `--selected-provider` and
  `--selected-model` (hidden), and the self-check runs with the same arguments, so it loads the configuration it
  will really run on. Without that, a file the choice made irrelevant could fail a reload that would have worked.
  `--reset` after a reload still restores the original flags, because the selection is a layer, not a flag rewrite.
- The command runs between turns, through the same boundary as the other commands.

## Probes

Real-PTY Q checks, against the fake provider: the id in the actual request, the label, provenance, a file edit
after the choice, refusal of an unknown provider and of one with a missing key, a bare id keeping the provider in
force, a reload with an invalid file provider, and a reset after the reload restoring the original flag.
Nine compiling mutations are caught (diary 37). One escaped first and exposed a probe that could not see a
refused selection being adopted; it now checks the live configuration still loads.

## Consequences

A selection is not saved: ask restarted by hand uses the configuration again. `providers.json` model lists are not
yet offered as choices, and Codex's account catalog is used only for limits, because 0038/0047 own discovery
and named connections. Selecting a model for a signed-out Codex or Anthropic account is accepted and fails on the
first request, like `--model`; only a preset's missing key is caught early.
The selected model does not enter the session archive, so resuming it later uses that run's configuration.
