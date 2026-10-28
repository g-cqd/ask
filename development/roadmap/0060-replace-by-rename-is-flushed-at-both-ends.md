---
status: done
blocked-by: []
date: 2026-10-24
---

# 0060 — Replace by rename is flushed at both ends

`fcheck` (the second analysis pass) found three production writers that rename a new file over an old one without making either end
durable. Done in ADR-0089, diary 2026-10-24 (43): the barrier flush before the rename and after it, in `AtomicFile`, `ProjectTrust`
(now through `AtomicFile`) and `ScopedFile`. Cost measured at about 0.35 ms per replace.

## Still owed

Nothing known. The `fcheck` warnings on test fixtures are left alone.
