---
status: not-started
blocked-by: []
date: 2026-10-20
decision: ADR-0036
---

# 0044 — Refresh Claude's credentials under the same lock

Codex's refresh runs under a lock beside the credential file, with a second look after taking it (ADR-0036), because its
refresh token is single use. `ClaudeAccess` has the same read, refresh, save shape and no lock, so two asks finding the
credentials expired could both refresh. First probe whether Claude's refresh tokens are single use: with a real
subscription, refresh the same token twice and see whether the second is refused. If they are, `CredentialLock` is
already there to use; if not, record that and close this entry.
