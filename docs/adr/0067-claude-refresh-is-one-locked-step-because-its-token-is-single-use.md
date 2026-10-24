---
status: accepted
date: 2026-10-24
---

# 0067 — Claude's refresh is one locked step, because its token is single use

## Context

Roadmap 0044 asked first whether Claude's refresh tokens are single use, because the answer decides whether `ClaudeAccess` needs the
lock `CodexAccess` has (ADR-0036). `ClaudeAccess` read, refreshed over the network and saved, with no exclusion across the call
(ADR-0039 made the save itself safe). The owner signed in a disposable named connection, `claude-a`, so the probe could spend
its grant without touching the real login. Diary 2026-10-24-16; the probe is archived in `docs/research/probes/ClaudeRefreshProbe.swift.txt`
and printed only statuses, error codes, booleans and 3-byte hash prefixes.

## The probes

All against Anthropic's real token endpoint, with ask's own request shape, on `claude-a` only.

- **Does a refresh rotate the refresh token?** HTTP 200, a different refresh token, a new access token. **CONFIRMED.**
- **Is the spent token refused when presented again?** HTTP 400 `invalid_grant`. **CONFIRMED**, so the lock is needed.
- **Does presenting a spent token punish the grant?** The newest token still refreshed (HTTP 200) right after. **REFUTED**: no
  family revocation was observed. This was one probe on one grant; it does not say a different server policy could not appear.
- **What does a race do?** Two refreshes of one token sent together: one HTTP 200, one 400 `invalid_grant`. **CONFIRMED.** Without a
  lock the loser reports a failed refresh although the winner just saved perfectly good credentials.
- **Does the response identify the account?** Yes: the account address and the organisation, on every refresh, and the same
  account as the stored one. **CONFIRMED**; this answers a question roadmap 0046 left open.
- Tokens and lifetimes: the access token had about 7.9 hours left when probed, and every response carried a refresh expiry.

## Decision

1. **Refreshing Claude's credentials is one locked step**, as Codex's: take a lock shared by every ask process, read what is stored
   again (another process may have refreshed while this one waited), and only then refresh, saving the whole replacement only if
   what is stored is still what was refreshed. A failed refresh leaves what was stored and is not retried, because the server may
   have spent the token. The wait is 30 s; past it the error is `lockUnavailable`, not a hang.
2. **Claude's lock has its own name** (`claude-refresh`), so a Codex refresh in the same credential file never holds it up.
3. **A named connection is held to its account.** If the refresh names a different account address than the one stored, the
   refresh is refused (`accountChanged`) and nothing is saved. The default sign-in is not held to one.
4. **Every failure reads as a sentence that says what to do**, and carries no token.

## Consequences

- Two asks that find the credentials expired refresh once between them; the second uses the first's result.
- An older ask without the lock can still race a newer one: the loser's `invalid_grant` is then real. Both builds must be current
  for the exclusion to hold.
- Not established: whether a server policy ever revokes a grant for reuse (it did not here), concurrent refreshes across more
  than two processes, and a real two-process race through `ask` itself (the tests use an in-process transport; the race tests pass
  without the lock for want of a timing hook, as Codex's do, and the lock-held tests are what prove it).
