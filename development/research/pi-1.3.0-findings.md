# Research note — pi 1.3.0 session handling

Notes from studying [earendil-works/pi](https://github.com/earendil-works/pi) 1.3.0 while designing ask's
sessions. Kept for what they taught about reliability, not as a target: ask's own requirements are in the
white paper and ADR-0013. Each row was observed by running pi's installed code with the probe named, not
by reading it. Nothing here is filed upstream.

Re-run a probe with `PI_VERSION=<v> node development/research/<probe>.mjs` before relying on a row.

| # | Area | pi 1.3.0 behaviour | ask behaviour | Probe | Kind |
|---|---|---|---|---|---|
| 1 | session load | torn final record dropped silently | dropped and reported | `probe-pi-session-parsing.mjs` | silent data loss |
| 2 | session load | corrupt mid-file line dropped silently | skipped and reported with its line | `probe-pi-session-parsing.mjs` | silent data loss |
| 3 | session load | corrupt header → **no entries at all** | every intact entry loads, header reported missing | `probe-pi-session-loading.mjs` | loses intact content |
| 4 | session load | unterminated final line → load **writes a newline to the file**, turning a torn fragment into a permanent corrupt line | load never writes; re-saving produces a clean log | `probe-pi-session-loading.mjs` | write on read |
| 5 | session context | unknown leaf id → silently the last entry | same fallback, reported | `probe-pi-session-parsing.mjs` | silent repair |
| 6 | session context | missing parent → context silently truncated at the gap | orphan re-rooted, subtree reachable, reported | `probe-pi-session-parsing.mjs` | silent repair |
| 7 | session context | duplicate id → the **last** entry wins | the **first** wins (children were written against it), reported | `probe-pi-session-loading.mjs` | ambiguous resolution |
| 8 | compaction | boundary off the active branch → summary plus later entries only; earlier messages dropped | compaction spliced out, raw messages kept, reported | `probe-pi-compaction-context.mjs` | loses intact content |

## Checked and not a divergence

| Area | Suspicion from reading the source | Result of running it |
|---|---|---|
| compaction | an older compaction inside the retained range is replayed, putting two summaries in context | the entry list keeps it for the UI; the model sees only the latest summary, as in ask |

## Resolved upstream

None yet.
