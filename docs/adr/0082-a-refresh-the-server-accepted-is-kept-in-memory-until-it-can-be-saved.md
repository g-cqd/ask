---
status: accepted
date: 2026-10-24
---

# 0082 — A refresh the server accepted is kept in memory until it can be saved

## Context

Refresh tokens rotate and are single use (ADR-0074, ADR-0036). `ClaudeAccess` and `CodexAccess` refresh under a lock shared by every
ask, then save the whole replacement under a second lock, only if the file still holds what was refreshed. If the save failed, after
the server had already spent the old token (the save lock held longer than the five seconds it is waited for, a full disk, a failed
rename), the access threw and dropped the response: the file kept the spent token, the next run was refused with `invalid_grant`,
and the user was told to sign in again. TLC found it in four steps (`docs/formal/CredentialRefresh.tla`, run with `MaySaveFail` on),
and tests reproduced it in both accessors (roadmap 0056, `docs/formal/REPORT.md`). A failure that was only transient cost the sign-in.

## Decision

1. **The rotated credentials are kept, and the request goes ahead with them.** On a failed save the pair the server issued is held in
   memory (`UnsavedRotation`), together with what the file still holds, and `auth` returns the fresh access token as if the save had
   worked. The request that caused the refresh has a valid token and is not failed for a storage problem.
2. **Every later call tries the save first.** It is the same compare-and-replace as before, against what the file held when the
   rotation happened. If it succeeds, nothing is held any more. If it finds something else in the file, the user signed out or in again
   meanwhile, and what they did stands: the held pair is dropped.
3. **While the file cannot take it, the held pair is what is used.** Requests use its access token. If that has expired too, the next
   refresh starts from its refresh token, which the server will accept, not from the spent one in the file; the save then replaces what
   the file held in one step.
4. **The same code in both accessors.** Claude's and Codex's accessors are twins over different credential types and errors, and stay so;
   the box they share is one small generic type.
5. **Not retried inside the call.** A retry loop would add seconds to a request when the lock is held and helps only when the lock frees
   up inside it; the next call is a retry that costs nothing.

## Supersedes

Roadmap 0045 required that "failed persistence is reported before a refreshed token is used for inference" and that "the old file
remains intact if the atomic save fails", and `CredentialRefreshRaceTests` pinned it ("reported and never used"). The second half still
holds: nothing is written when the save fails. The first half rested on the old file remaining a usable sign-in, which is true only
while the server has not accepted the refresh. Once it has, the old token is spent, and refusing to use the replacement protects
nothing and costs the sign-in. That test now says the replacement is used and held.

What the old rule also wanted, that a storage failure is not silent, is **not** provided here: the providers have no channel to the
transcript, so the user is not told that a sign-in could not be saved (`rotationIsUnsaved` is the hook). That is owed.

## Consequences

The refresh token is no longer lost to a transient failure while ask keeps running, which is how ask is used. What is **not** covered:
if ask exits before any later call saves it (a one-shot `-p` run whose save failed), the file still holds the spent token and the next
run is refused, as before. Nothing here writes the pair anywhere else; a second copy outside the credential file would be a second
place a secret lives, and that is a decision for its own record.

## Probes

Unit tests on both accessors: the request goes ahead, the next call saves and sends no second refresh, a refresh while the file still
cannot be written starts from the held token, a lock that frees up in the middle of that refresh lets one step bring the file up to
date, and a sign-in made meanwhile is not overwritten. Fourteen compiling mutants, all caught by named assertions.

## Addendum (2026-10-24, from the second analysis pass)

A TLA+ model of the fix (`ask-formal-report/tla/CredentialRefreshFixed.tla`) found one case this record does not state: **a second ask
process is refused while the first holds a rotation it could not save.** The held pair is in the first process's memory and the file
still holds the spent token, so the second process reads it, offers it, and gets `invalid_grant` (`refreshFailed`). Confirmed with the real
code in `ClaudeRefreshSaveFailureTests`: the refusal leaves the file as it was, and once the first process's next call saves its pair the
second process uses it with nothing sent. It is rare (it needs a failed save and a second process in the same stretch) and it clears
itself. Lifting it would mean the first process writing the pair somewhere a second one can read, which is the second place for a secret
this decision declined; or holding the refresh lock until saved, which would make every other ask wait for a lock held by a failing disk.
Neither is taken.

## Addendum (2026-10-25)

The person is now told when this happens: once, with the reason, through the notice channel (ADR-0091).
