---
status: not-started
blocked-by: []
date: 2026-10-24
---

# 0056 — Keep the rotated credentials when their save fails

Found by model checking (`docs/formal/CredentialRefresh.tla`) and **confirmed by tests**
(`ClaudeRefreshSaveFailureTests`, two known issues). `ClaudeAccess.auth` and `CodexAccess.credentials` refresh under the refresh lock,
then save under the save lock. When the server has accepted the refresh and the save then fails (`CredentialFileError.locked` after 5 s,
a full disk, a failed rename), the access throws `.storage` and drops the response. The file still holds the old refresh token, which is
single use (ADR-0073), so the next ask offers a spent token, is refused with `invalid_grant`, and tells the user to run `ask login`.
A transient failure costs the sign-in.

Codex has the same shape; only Claude is tested. Antigravity does not rotate its token (diary 2026-10-24-23), so it is not affected.

## Decide

Retry the save before giving up (the save lock is released in milliseconds in practice), and, if it still fails, say that the credentials
were rotated and could not be stored, rather than a generic storage error. Whether to return the fresh access token for the current
request when the save fails is a separate choice: it serves this request and leaves the next one signed out.

Remove the two `withKnownIssue` wrappers in `ClaudeRefreshSaveFailureTests` when the fix lands: a known issue that stops failing is
itself reported as a failure.
