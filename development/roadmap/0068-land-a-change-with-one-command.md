---
status: done
blocked-by: []
date: 2026-10-25
---

# 0068 — Land a change with one command: claimed record numbers, the gate, the merge

Several agents work in parallel worktrees of one repository (`git worktree list` shows four today), and each takes the next ADR, diary and roadmap
number it can see. Two of them can see the same number, and git cannot tell, because the two records have different file names: this session
found **two ADR 0095s** and **two diary 06s** that no merge conflict reported. The repair is a renumbering commit and a second run of the gate.

**Evidence** (`git log --oneline -i --grep=renumber`): **17 of 410 commits** are renumberings, 12 of them since 2026-10-23 (8 on the 24th alone), and
there have been 76 commits and 17 merges since the 24th. Each renumbering is followed by the same hand-done ritual: fetch, merge `origin/main`, rename,
rewrite the cross-references, rerun the gate, fast-forward, remove the worktree.

## The work

1. **`Scripts/next-number.sh adr|diary|roadmap`** prints the next free number across **every** place a number can live: `origin/main`, local `main`,
   every local branch, and every worktree's uncommitted files. A diary number is per day.
2. **Claims are refs.** Worktrees share one object store and one set of refs, so `git update-ref refs/claims/adr-0103 HEAD 0000000000000000000000000000000000000000`
   is an **atomic** reservation: it fails if the ref exists. `next-number.sh --claim` takes the number and keeps the ref until the record is on
   `origin/main`. Open: whether an agent in a separate clone is possible, in which case a ref does not reach it; it does not today.
3. **`Scripts/land.sh`** fetches, refuses a tree in which two records share a number or a diary has a gap it did not make, merges `origin/main`,
   runs `Scripts/quality.sh --check`, fast-forwards `main` from the main checkout, removes its own worktree and branch, and **never pushes**.
4. A documentation test that **no two ADRs, roadmap entries or diary files of a day share a number**, which the layout tests do not say today.

## Done when

A probe in a throwaway repository shows: eight concurrent claimants get eight distinct numbers; the next number accounts for a record that exists only on an
unmerged branch; `land.sh` refuses a tree with a duplicated number and lands a clean one; and the claim ref is released when the record is merged.
The probe is broken once on purpose (a script that takes the number without the ref) and shown to fail.

## Implemented (ADR-0107)

`Scripts/next-number.sh` scans branch trees, origin/main, all worktree files, and shared claims. `--claim` atomically reserves; publication releases claims on subsequent runs.
`Scripts/land.sh` integrates local main and origin/main, checks duplicate numbers and new diary gaps, gates, checks moving refs, fast-forwards local main, and cleans up its own task only.
Use `--keep` to retain the task worktree. Neither script pushes. The quality entry point runs the real duplicate-number check and throwaway workflow tests.

The concurrent test was deliberately broken by deleting the expected-old ref argument and failed; restored code passes. Diary 2026-10-25-21 records the evidence.
Still owed: full repository gate and an actual local landing with the script.

## Not claimed

That a claim removes every collision: a person typing a number by hand still can, so the test of item 4 stays.

## Closed (2026-10-31): the first real landing

The record cleanup of 2026-10-31 (`47856b7`) was landed with `Scripts/land.sh` from a worktree made from `origin/main`: it fetched,
merged, validated the records, ran the full gate and fast-forwarded local main. It then failed to delete the task branch: `git branch
-d` compares a branch with its upstream, `origin/main` here, which a landing never pushes to. The branch was deleted by hand once main
was checked to hold it.

- Fix: `land.py` checks that main holds the branch (`merge-base --is-ancestor`), then deletes it with `-D`.
- `Scripts/test-land.py` (a gate stage): a scratch repository with a bare origin and a task worktree made from `origin/main` lands end to
  end, with a stub gate; main moves to the task, the worktree and branch are gone, and origin is untouched. Red before the fix with the
  live error, green after.
- Open question, unchanged: an agent in a separate clone, which a claim ref does not reach.
