---
status: accepted
date: 2026-10-24
---

# 0083 — A job's output is searched as two runs and cut only between characters

## Context

A command's unread output is kept as its first and last `keeping` bytes with a count of what fell between (`OutputBuffer`), so memory
is bounded however much it prints, and a long summary request clips text the same way (`Compaction.clipped`). Modelling the buffer in
Lean (`docs/formal/lean/OutputBuffer.lean`) showed two faults, confirmed by tests and then by reading the code (roadmap 0057,
`docs/formal/REPORT.md`):

- `Job.wait(for:)` searched `head + tail`, which closes the gap the omitted middle left, so a text straddling it was reported
  `found` that the command never printed. The real binary showed it: a job printing 1.5 MiB with `Re` ending the kept head and `ad`
  starting the kept tail answered `[job-1 printed "Read"]`.
- Both ends are byte cuts, decoded one side at a time, so a character of two to four bytes on a cut became U+FFFD.

## Decision

1. **The two ends are two runs.** `OutputBuffer.contains(_:)` searches the head and the tail separately when bytes were omitted: a text
   cannot span a gap it never crossed. When nothing was omitted the head and the tail are the stream, adjacent, and the join is
   searched. An empty needle is never found. `kept` stays for counting and comparing the ends and says it is not for searching.
2. **A text whose first bytes were dropped is not found.** That is a limit, not a defect: the buffer cannot see what it dropped. A
   false negative of this kind is accepted; a false positive is not. (The streaming path, which sees output as it arrives, is not
   affected.)
3. **Cuts fall between characters.** `UTF8Cut.droppingPartialEnd` and `droppingPartialStart` (in `AskAgentCore`, which `AskTools` already
   uses) take a partial character off a head's end or a tail's start: at most three bytes each, and nothing when the cut is already on a
   boundary. Bytes that are not text are cut the same way and never crash.
4. **The count stays true.** The omission note counts every byte the text does not show, the cut characters' bytes included, so what is
   shown plus what is counted is the stream.
5. **A stream nothing was omitted from is decoded whole.** Its head and tail are adjacent, and a character straddling them is one
   character; decoding them separately, as `text` did, showed U+FFFD for it. This one was not in the report.

## What this does not change

`OutputCap` already cuts on scalar boundaries and sits in front of the tool result, so the `OutputBuffer` cut at 512 KiB is hidden from
the model unless the cap is raised; the fix there is for correctness and for the file and any larger cap. `Compaction.clipped` is
reachable (`/compact` clips tool results to 400 bytes). `OutputCap.scalarCut` has its own boundary logic and was left alone.

## Probes

Unit tests, including an exhaustive check over every cut of a string with one-, two-, three- and four-byte characters and a real job
whose output straddles the gap. Twenty-three compiling mutants. The real binary for the join (`Scripts/probe-wait-gap.py`, with a
control). Not probed with the real binary for the cuts: see diary 2026-10-24 (36).
