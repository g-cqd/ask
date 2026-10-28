---
status: accepted
amends: ADR-0012
amended-by: ADR-0014
date: 2026-10-18
---

# 0013 — Damaged sessions load by default, and pi findings stay in this workspace

> **Amended by [ADR-0014](0014-our-own-bar-not-a-reference.md).** The decision stands on its own merits,
> reliability, rather than on comparison with pi. The findings file moved to `development/research/`.

## Context

ADR-0012 made ask strict where pi 1.3.0 silently drops damaged records, and listed an explicit recovery
mode as future work. Two decisions by the user change that:

1. **ask must be at least as convenient as pi.** A strict loader that refuses a corrupt session is less
   convenient than pi's best-effort loader, whatever its reasons.
2. **pi findings are not filed upstream.** They are recorded in this workspace.

## The probes behind the design

Running pi 1.3.0's own `loadEntriesFromFile`, `parseSessionEntries` and `buildContextEntries` on damaged
files (`Scripts/probe-pi-session-*.mjs`, `Scripts/probe-pi-compaction-context.mjs`) gave the baseline that
"at least as convenient" has to beat. pi drops torn and corrupt records silently, loads **nothing** when
the header is corrupt, **writes a newline into the file during load**, resolves duplicates to the last
one, and drops every message before a compaction whose boundary is off its branch. The full list, with
probes, is `docs/PI-FINDINGS.md`.

## Decision

1. **`SessionLog.recover` is how a session opens.** It keeps everything pi keeps and more: orphans are
   re-rooted rather than truncated, a bad compaction is spliced out rather than hiding earlier messages,
   and a corrupt header does not cost the session. Every repair is a `SessionLogIssue` with its line, so
   nothing is silent.
2. **It refuses only what cannot be repaired safely**: an archive over the size limit, and a format
   version newer than this build, which it cannot interpret without guessing.
3. **Loading never writes.** Repairs exist in memory until the session is saved, and re-saving produces a
   log that decodes strictly with no issues. The file store will preserve the damaged original rather than
   overwrite it.
4. **`SessionLog.decode` stays, strict**, as a thin wrapper over the same parser: one parser, two policies.
5. **pi findings go in `docs/PI-FINDINGS.md`, never upstream.** This replaces ADR-0012's "offered to the
   user" clause. The rest of ADR-0012 stands.

## Consequences

- A user with a damaged session gets their session, plus a list of exactly what was repaired. The UI must
  surface that list; a repair nobody sees is pi's silence with extra steps.
- The issue list makes recovery testable case by case; 16 recovery tests pin it, and ten compiling
  mutations of the repair logic each turned the suite red.
- Re-rooting an orphan is a judgement: its true parent is unknowable once the parent's line is corrupt.
  Attaching it to "the previous line" would usually be right and sometimes silently wrong, so it is not
  done.
