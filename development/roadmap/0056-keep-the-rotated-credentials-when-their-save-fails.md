---
status: done
blocked-by: []
date: 2026-10-24
---

# 0056 — Keep the rotated credentials when their save fails

Found by model checking (`development/formal/CredentialRefresh.tla`) and **confirmed by tests**
(`ClaudeRefreshSaveFailureTests`, two known issues, now real tests). `ClaudeAccess.auth` and `CodexAccess.credentials` refresh under the refresh lock,
then save under the save lock. When the server has accepted the refresh and the save then fails (`CredentialFileError.locked` after 5 s,
a full disk, a failed rename), the access throws `.storage` and drops the response. The file still holds the old refresh token, which is
single use (ADR-0073), so the next ask offers a spent token, is refused with `invalid_grant`, and tells the user to run `ask login`.
A transient failure costs the sign-in.

Codex has the same shape; only Claude is tested. Antigravity does not rotate its token (diary 2026-10-24-23), so it is not affected.

## Done (2026-10-24, ADR-0082, diary 2026-10-24-34)

The rotated pair the server issued is kept in memory when its save fails, the request goes ahead with it, and every later call
saves it first, in both accessors. Not covered: ask exiting before a later call saves it, as in a one-shot `-p` run whose save failed.
The known-issue wrappers are gone, replaced by tests of the behaviour.

## What was decided

Retrying inside the call was not chosen (ADR-0082): it only helps when the lock frees up within it, and the next call is a free
retry. Returning the fresh token for the current request was chosen, which the original note had left as a separate choice.

## Update (2026-10-25, ADR-0091)

The one thing the fix left out is done: a notice, once per failure, naming the reason and what to expect (diary 2026-10-25 (02)). Still
not covered: ask exiting before a later request saves the pair, and a second process seeing the spent token.
