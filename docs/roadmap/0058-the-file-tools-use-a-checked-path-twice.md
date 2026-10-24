---
status: done
blocked-by: []
date: 2026-10-24
---

# 0058 — The file tools use a checked path twice

ADR-0035 recorded that a path check and its use are two steps. This entry measured it and closed it for `read`, `write` and `edit`
(ADR-0085, diary 2026-10-24 (38)).

## Done (2026-10-24)

A racing job landed 2 of 6,000 writes in ask's configuration directory, and a swap at the right instant read its credentials file.
Under a restricted policy the tools now open the object, authorize where the kernel says it is, and use only the descriptor (for
writes, a verified directory descriptor and `openat`, `mkdirat`, `renameat`). 30,000 racing writes afterwards: none landed.

## Still owed

Hard links (see ADR-0085, why Seatbelt covers it); nothing else known.
