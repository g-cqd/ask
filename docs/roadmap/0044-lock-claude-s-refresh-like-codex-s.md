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
already there to use; if not, record that and close this entry. (Since ADR-0039, `CredentialLock.acquire` takes a lock name, and
Claude's refresh already saves only if nothing changed meanwhile. What is still missing is exclusion across the network call.)

## How to run the probe (two named Claude connections, one account)

A named Claude connection (ADR-0040) makes the question testable with a single account: two sign-ins are two separate grants.
Commands, in fish, from the repository:

```fish
.build/release/ask login claude --name claude-a
.build/release/ask login claude --name claude-b
.build/release/ask connections
```

Each login prints a URL; open it, sign in, paste the `code#state` it shows. Then check, without printing any token:

1. Both are registered, with different refresh tokens.
2. Each, and the default `anthropic` sign-in, still answers a request after the other was created. Signing in again may revoke
   older grants; if it does, that is the finding, and `ask login claude` repairs the default.
3. Mark one connection's access token expired in its own credential file and run `ask --provider claude-a --print x`: ask must
   refresh on the real server. The other connection and the default must be left intact, and the file mode stays 0600.
4. Whether the refresh response identifies the account (ADR-0040 checks that for Codex only).
5. Whether the **spent** refresh token is refused when presented a second time. Refused: the tokens are single use and the lock
   across the refresh is needed. Accepted: record that and close this entry.

Not yet run. A usage-limit 429 is inconclusive, not a failure.

