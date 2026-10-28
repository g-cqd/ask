---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0020
---

# 0019 — The model proposes sandboxing; only the user widens it

ADR-0020's model-facing half, delivered in three slices.

## Delivered

- **Per call** (ADR-0054, diary 49): `bash`, `read`, `write` and `edit` accept an optional `sandbox` object
  with network, read and write capabilities. A narrowing applies atomically; an invalid request does not run.
  Job-control tools do not advertise a new sandbox: an existing process keeps the profile it started with.
- **Approval** (ADR-0055, diary 52): a widening in the screen asks the user, naming the command/path and requested
  capabilities. y once, a for the session (in memory), n or Esc no; Ctrl-C still aborts. Under `-p` a widening
  is refused unless the user already allowed it.
- **Whole conversation** (ADR-0057, diary 56): `narrow_sandbox` narrows every later dispatch. Further changes
  preserve dimensions they do not name. Undoing it requires approval; unrelated session grants cannot reset it.
  Stop running jobs first, since they cannot adopt another Seatbelt profile. The state survives loop rebuilds,
  `/model` and configuration changes; `/new`, `/resume` and process replacement clear it.
- **The active policy** is appended to each request's stable system prefix, independently of archived tool results,
  so compaction cannot erase it. Denials name the capability and say widening is the user's decision.
- **Headless flags:** the existing `--read`, `--write`, `--network` and `--no-sandbox` supply the user-only
  override (ADR-0043). The original proposal's differently named `--sandbox`/`--allow-*` flags are not duplicated;
  `sandbox.denyRead` remains available in configuration.

0013, the interactive screen, was the original blocker and is complete.

## Boundaries

Model-proposed narrowing is an in-memory layer on the current conversation, not a persistent restriction on an
archive. Saved user-configured strict scopes resume separately (ADR-0045). An existing child process is never
claimed to have changed its kernel profile; file-tool canonicalization races remain documented separately.
