---
status: not-started
blocked-by: []
date: 2026-10-20
---

# 0045 — Credential transactions preserve concurrent connections

Foundation for named connections (0046). Existing saves read, change and atomically replace the credential file;
Codex access holds a refresh lock, but login, logout and the other credential writers do not all participate in it.
Whether concurrent read-merge-write operations can lose one another's updates must be probed before adding accounts.

Done when all writers use one short cross-process read-change-save transaction, preserving unknown supported records
and every unrelated connection, and refreshing uses a separately defined connection-scoped exclusion rule. Do not
hold a global file-write lock over a network request. Probe the actual Darwin lock behavior from separate processes;
a task race in one process alone is not evidence of the cross-process contract.

Required regression gates, red before implementation:

- Two concurrent saves of different connections retain both, including a key login alongside an OAuth refresh.
- Two refreshes of the same connection spend one rotating token; different connections can refresh independently.
- Logout or replacement during a pending refresh wins: an old response cannot restore credentials the user removed.
- Failed/cancelled/uncertain refresh is not automatically retried. Failed persistence is reported before a refreshed
  token is used for inference. The old file remains intact if the atomic save fails.
- A process dying releases its locks. Cancellation closes lock descriptors. Nested locking cannot self-deadlock.
- Reading legacy credentials never rewrites them. Damaged credentials are never silently overwritten.

Use a generation or compare-and-replace check inside the short write transaction to detect logout/replacement while
refresh was awaiting the server; pin that rule with an explicitly gated response, not a sleep. Choose the precise
on-disk envelope and lock names after these probes, then record the decision in an ADR. No dependency or generic
storage framework is justified merely by adding another account.
