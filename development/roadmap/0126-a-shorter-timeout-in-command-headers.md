---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0126 — A shorter way to write a command's timeout

Owner wish (2026-10-28 23:02): find a more compact way to write the timeout in command headers (0080 writes `timeout 2 min`).

## To decide with the owner

Candidates, shortest first: `⏱2m` (a symbol and compact units), `2m` alone after the tool name, `≤2m`. Units would be `45s`, `2m`,
`1m30s`, `1h`. `ui.localizedDurations` may then only govern elapsed times.

## Owner's answer (2026-10-28)

The proposed short forms (`⏱2m`, `2m`, `≤2m`) are rejected. Do not use them. Still open: another approach, to be proposed as something other
than a cut-down spelling (for example dropping the word when the unit says it, or showing the timeout only when it is not the default).
