---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0088 — Active memory is 21.5 MiB against a 20 MiB budget

ADR-0122: the owner set idle 15 MiB and active 20 MiB, assessed on a loaded machine. `Scripts/measure-budgets.py` samples the
resident size right after a `read` tool call is shown. Loaded, 15 runs, release build: idle 12,384 KiB, **active 22,000 KiB** (p95
22,112; min 21,920) against 20,480. The turn adds about 9.6 MiB.

## Plan

1. Separate what the measurement counts. RSS includes shared system libraries; compare it with the physical footprint (`footprint`
   or `vmmap -summary`) before and after the turn, and say which one the budget means.
2. Attribute the growth: `vmmap` at idle and after the turn, diffed by region (malloc zones, stacks, mapped files). Candidates,
   all unmeasured: the first request's connection pool and TLS state, the JSON codec, the session file, transcript and screen
   buffers, the tool run (a thread and a pipe), a read buffer sized for the largest file.
3. Fix the largest first, with a before and after run each. No budget change without the owner.

## Done when

The loaded median is under 20,480 KiB with the fix named in a diary, or the owner moves the limit.

## Measured (2026-10-29, release build, `footprint` and `heap`)

Step 1 of the plan, done. The budget script reads RSS, which counts pages of system libraries that every process maps and that ask
did not allocate. The physical footprint is ask's own cost, and is what Activity Monitor's Memory column shows.

| | RSS | physical footprint |
| --- | --- | --- |
| idle, fresh start | 14.6 MB | 3.6 MB |
| after one turn with a `read` tool | 23.1 MB | 6.6 MB |
| a copy of the owner's biggest session resumed (1,930 responses, 8.9 MB file) | 53.2 MB | 38.8 MB |

A turn adds 3 MB of footprint but 8.4 MB of RSS: the networking and security libraries becoming resident. Against the footprint, both
budgets hold by a factor of three. **Owner decision needed: which one does the 15 and 20 MiB budget mean?** Recommended: the footprint,
plus a new budget for what a long session costs.

What a long session holds (`heap`, 23.8 MB allocated of the 38.8): Swift strings 12 MB (32,000 of them); one array of the whole
transcript's wrapped screen lines, `[ScreenComposer.Line]`, 3.1 MB; two retained arrays of the opening `ConversationUpdate`s, 1.7 MB,
which nothing needs once the screen is open; the session's entries 0.8 MB; file-path strings from the project index 0.8 MB.

## Plan from here

1. Free the opening updates after the screen has applied them (about 1.7 MB, no behaviour change).
2. The owner's idea, a screen that does not keep the whole conversation laid out: keep per-item line counts for scrolling and build the
   wrapped lines of the visible window and a margin, not of every item. Saves the 3 MB array and the strings inside it (the strings are
   most of the 12 MB; attribute them by item kind first).
3. Let the session tree keep large tool results and responses on disk, read back when an item is opened or the context is built.
4. Re-measure each with the footprint and the long session; add the long-session figure to `Scripts/measure-budgets.py`.

