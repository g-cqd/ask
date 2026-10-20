---
status: accepted
date: 2026-10-20
---

# 0045 — A session records its strict sandbox, and a resume keeps it

## Context

Roadmap 0042: "record the policy in the session, so a resumed session keeps its sandbox even when the flags differ".
A session started with `--network none` and continued with plain `ask --continue` would otherwise run with the
network on, which is not what its owner chose for it.

## Decision

- **A `sandbox` record**, `{"network":…,"type":"sandbox","write":[…]}`, beside the `leaf` records and outside the
  entry chain. It holds only the strict settings (write scopes, network level). The latest one wins on replay; a
  snapshot (a damaged-file rewrite, a fork) carries it; a failed write rolls it back in memory.
- **Why not an entry.** An older ask skips a record it cannot parse as one malformed line. An unknown *entry* kind
  would be skipped the same way, but every later entry would then lose its parent and become an orphan root.
  A separate record costs an old reader one line and a repair notice; probed.
- **Resuming** (`--continue`, `--resume`, `/resume`) adds the record as a narrowing layer above the files and below the
  flags: it can only narrow, and a `--network` or `--write` flag is the user widening on purpose, so the record does
  not override what a flag set. When it changes anything, ask says so. `/new` drops it.
- **Recording** happens at the start of a run, only when the effective strict settings differ from the record.
  A session that never ran strict gets no record; an unsandboxed (`--no-sandbox`) run records nothing.
- **Read without copying**: the recorder exposes the record under its lock, since a tree copy held across an append
  would copy the whole tree.

## Probes

Unit tests pin the bytes, replay, rollback, old-reader resilience and layering. Probe O (`-p`): a `--network none`
session records it; `--continue` keeps it (curl exit 7) and says so without re-recording; `--continue --network
localhost` widens and re-records; a new session is unaffected and records nothing. Probe S (screen): `/resume`
shows "sandbox: workspace only, no network"; `/new` drops it. Nine mutations caught (diary 41).

## Consequences

Opening a 1,000-entry session costs about 2% more (+60 µs p50, quartiles overlapping); a first version that added the
record's keys to the shared key set cost +7% and was changed (diary 41). An older ask that rewrites a newer session
drops the record (keeping the original as `.damaged`). Only write and network are recorded; `denyRead` and the
default protections come from configuration, as they do for a new session.
AemiJSON emits invalid JSON for two keyed containers on one encoder (issue #4, being fixed upstream); the record is
written through a single container, so nothing here depends on that fix.
