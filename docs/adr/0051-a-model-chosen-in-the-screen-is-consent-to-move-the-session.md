---
status: accepted
date: 2026-10-20
---

# 0051 — A model chosen in the screen is consent to move the session; resuming drops the choice

## Context

Two decisions met when the named-connections work (ADR-0048) and the interactive commands (ADR-0042) merged:

- ADR-0048 pins a resumed session to the destination it recorded unless `--provider` names another, and refuses to move
  a session with history to another connection without explicit consent.
- ADR-0042's `/model` is a run-local choice above every configuration layer.

Merged as written, a `/model` choice in a resumed session was overridden by the pin (the request kept the old model),
and `--model` from the launch beat a later `/model`. Probed: the request carried the launch flag's model after
`/model vendor/model:tag`.

## Decision

- **Precedence**: a `/model` choice, then `--model`, then the resumed session's recorded model, then the configuration.
  The resume pin applies only when neither `--provider` nor a `/model` choice names a destination.
- **A `/model` choice is consent.** Typing it is the user saying where the session goes, so moving a session with
  history to another connection is recorded as a new destination, not refused.
- **`/resume` drops this run's `/model` choice**: a resumed session goes back to where it was sent, rather than silently
  moving to whatever model was picked for another conversation. `/new` keeps the choice: a new session has no history
  to move.

## Probes

Real-PTY probe T, two sessions recorded on two models: a resumed session goes where it was sent; `/model` overrides it;
`/model` to another provider sends nothing to the old one and records the move as consented; `/resume` into the other
session returns to that session's own model. Four mutations caught (pin ignoring the choice, `--model` beating it,
the choice not counting as consent, `/resume` keeping it). Diary 46.

## Consequences

The connections tests and probes (`probe-connections.py`, `probe-anthropic-env.py`) are unchanged and pass: the rules
only differ when a `/model` choice exists, which those flows never make.
