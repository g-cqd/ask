# pi findings

Defects and rejected trade-offs found in [earendil-works/pi](https://github.com/earendil-works/pi) while
porting its design. **Recorded here, never filed upstream** (ADR-0013). Each row was found by running pi's
own installed code, not by reading it, and each has an ask test marked `Diverges from pi <version>`.

Append a row per finding. Re-run the probe against a new pi release with `PI_VERSION=<v>` before
assuming a row still holds; a fixed row moves to *Resolved upstream* with the version that fixed it.

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
