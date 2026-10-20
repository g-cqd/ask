---
status: accepted
date: 2026-10-20
---

# 0040 — Named connections are registered destinations with stable identities

## Context

A user wants two accounts of one provider (a personal and a work ChatGPT plan) at the same time. Until now a provider had one
sign-in and its name was its identity, so a second account meant signing the first one out. Roadmap 0046 proposed a design;
this records what was built and what the probes said. Credential transactions (ADR-0039) and the account-scoped catalog
(ADR-0037) were the prerequisites.

## The probes

Ledger in `docs/diary/2026-10-20-31.md`.

- **Does the credential envelope keep records it does not know?** **REFUTED**: any save dropped them. Fixed by keeping each
  unknown value as its source bytes (AemiJSON container spans), so a 20-digit integer, a 25-digit decimal and `1e-100`
  survive byte for byte; 5 tests, 3 failed before.
- **Does an older ask refuse a session in the new format?** **CONFIRMED** with the `main` binary against a session the new
  binary wrote: exit 66, and the file was left byte-identical.
- **Does the first design resume every existing session?** **REFUTED by the real binary**: it refused every session recorded
  before this feature (exit 78) unless `--provider` was passed. Found in review, reproduced, fixed (below).
- **Do all the rules fail without their test?** 12 mutations, **12 killed**, after correcting a test filter and two mutations
  that did not compile.

## Decision

1. **A connection is a directory**, `connections/<uuid>/`, holding its own credential file (record plus secrets, written as one
   transaction), its own refresh and save locks and its own model-catalog cache. The default sign-ins (`codex`, `anthropic`)
   are untouched and keep using `credentials.json`; nothing is migrated.
2. **Two identities.** The id never changes. The `authorizationID` changes on sign-out, removal and a deliberate change of
   remote account, so "the same name" never silently means "the same authority". A rename changes neither.
3. **Names** are lower-case, 1–64 ASCII letters, digits, `.`, `_`, `-`, starting with a letter or digit. They may not equal a
   built-in, a preset, or an entry in `providers.json`, at registration, at rename and at selection. Allocation is serialised
   by a registry lock; a busy lock is reported, never worked around.
4. **A pending sign-in cannot undo a logout**, and signing in as a different remote account needs `--replace-account`. A Codex
   refresh for a named connection that returns a different account is refused (`accountChanged`). Claude's is not checked: whether
   its refresh response identifies the account was not probed.
5. **`--provider` selects a connection.** There is no second selector and no failover: a quota or error never moves a prompt to
   another account. Named connections ignore `ANTHROPIC_API_KEY` and endpoint overrides.
6. **Sessions record where they went**, as a `destination` entry (connection id, authorization id, label, raw model id; never a
   token or an email), invisible to the model, to replay and to compaction. Resume follows the recorded destination, even after
   a rename, unless `--provider` is given, which is the consent. If the connection was signed out or its account replaced,
   the session is refused until the user chooses. A reload does not turn an old `--provider` into fresh consent.
7. **History from before this feature may continue on an unnamed provider** (which is all it could have used) and is refused
   for a named connection unless `--provider` is explicit.
8. **Session format 2.** Version 1 is still read; the first change upgrades it and keeps the original as `.version-1`. An older
   ask refuses version 2 rather than dropping the routing record.
9. **A newer registration schema is refused**, not normalised by an older writer.

## Consequences

- Every register, rename, sign-out and removal takes a lock on the registry directory. A first `ask login X --name` creates
  `connections/` in the config directory.
- Removal clears secrets and retires the name's id, but the directory and its catalog cache remain. The cache holds model ids
  and limits only.
- `ask logout` with no name signs out every named connection too, and reports if some registrations were unreadable.
- Not done: model aliases (0047); a picker in the interface; `--json`; named connections for key-based providers.
- **Not verified:** a real browser sign-in with `--name`, a named Claude sign-in, and the OAuth account chooser. All were
  exercised only with synthetic credentials and no network.
- Idle memory is about 0.3 MiB higher (9160 to 9488 KiB, non-overlapping ranges), consistent with a binary 250 KB larger.
