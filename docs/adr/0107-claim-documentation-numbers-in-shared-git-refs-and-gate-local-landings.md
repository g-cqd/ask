---
status: accepted
date: 2026-10-25
---

# 0107 — Claim documentation numbers in shared git refs and gate local landings

## Context

Concurrent worktrees repeatedly chose the same ADR and diary numbers. Distinct filenames merge cleanly even when their numbers collide.
A number must account for unpublished branches and files, not only the currently checked-out directory. Local main and origin/main can both move during a gate.

## Decision

1. `Scripts/next-number.sh adr|diary|roadmap` scans origin/main, local branches, uncommitted files in every worktree, and existing claim refs.
   Diary numbers are per local date; `--date YYYY-MM-DD` makes that choice explicit. Return the highest occupied number plus one; never recycle a gap silently.
2. `--claim` compare-and-creates `refs/claims/<kind>-<number>` (diary includes the date) with `git update-ref`'s expected-old zero object id.
   A concurrent loss retries the next number; other errors fail. Reflogs identify the claiming worktree. Inspection alone is not a reservation.
3. Keep claims through local landing. On subsequent allocator/landing runs, release only claims whose record number is present on origin/main.
   An abandoned unpublished claim needs deliberate inspection and manual removal, not timeout-based reassignment while an agent may still be working.
4. `Scripts/land.sh` operates only on a clean named task worktree, with exactly one clean main checkout. A common-directory lock serializes cooperating landings.
   It fetches, merges local main and origin/main, refuses duplicate record numbers and newly introduced diary gaps, runs the repository's full quality gate,
   fetches again, and refuses if either main moved during the gate. Integration conflicts and failures keep the task worktree for repair.
5. After a successful gate, fast-forward local main, remove only this task's worktree and branch (or retain them with `--keep`), and never push.
   Existing diary gaps do not block unrelated work; a newly introduced gap must be resolved before landing.
6. The quality entry point checks duplicate numbers for all three record kinds and runs throwaway-repository workflow tests.

## Evidence

Diary 2026-10-25-21 records the eight-claimant experiment, its broken negative control, and workflow tests.
Deleting the expected-old argument made the actual concurrent-claim test fail; restored code passes.
The landing fixture uses a real local bare remote and asserts its main ref is unchanged.

## Consequences

These are clone-local reservations, not distributed coordination. A separate clone, manual number choice, or noncooperating git command can still race.
The duplicate gate remains necessary. The script does not promise a transaction across arbitrary external git operations during main's checkout update.

Local main must have its own worktree. Dirty trees, stale locks, conflicts, moving refs, and failed gates stop rather than discard work.
Inspect `ask-land.lock/owner` before manually removing a stale lock. Different diary claimants may need to land in number order to avoid a newly introduced gap.
No runtime code or shipping dependency is added; the cost is extra development-time git subprocesses and workflow tests.
