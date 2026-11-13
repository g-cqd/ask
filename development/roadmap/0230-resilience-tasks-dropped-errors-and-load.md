---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0230 — Resilience: background tasks, dropped write errors, the screen under load

Engineering plan phase C, the owner's choices of 2026-11-13 (a gate rule for `try?`).

1. Every unstructured `Task {}` and `Task.detached` (110, 2026-11-13) audited: what it captures (weakly when it outlives a session),
   who cancels it, what it races. A session's tasks become children of a per-session group cancelled on switch; a test per
   lifecycle event that none of the old session's is left.
2. The 35 `try?` around writes: each surfaced (a notice, a retry) or justified with a `// try?:` reason. The gate refuses a new
   `try?` around a write without one.
3. Under load (notes n18, n55): a probe mode with artificial CPU load for the input path, and the input loop's priority checked.

## Done when

The audit table is in the diary, the gate rule is on, and the input probes pass under load.
