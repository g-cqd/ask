---
status: not-started
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

## Not claimed

That a claim removes every collision: a person typing a number by hand still can, so the test of item 4 stays.
