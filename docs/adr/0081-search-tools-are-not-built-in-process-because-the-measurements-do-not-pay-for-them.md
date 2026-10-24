---
status: accepted
date: 2026-10-24
---

# 0081 — Search tools are not built in process, because the measurements do not pay for them

## Context

Roadmap 0043 proposed `grep`, `find` and `ls` tools in place of `bash rg`, and said to measure first: the same search both ways, for
time and for tokens, and the cost of a tool definition sent with every request. Measured on this repository (663 files, 3.7 MB of
sources and tests) on a loaded development machine (load about 20), with ripgrep 15.2.0. Scripts and raw output are in
`docs/research/search-tools/`; the diary is 2026-10-24-30.

## The probes

- **What `bash rg` costs.** Through a shell, `rg` takes 11 to 28 ms for these queries (median; p95 13 to 41 ms), of which about 6 ms is
  the shell. ask's sandboxed bash adds its own spawn (about 10 ms, ADR-0053).
- **What an in-process search costs.** Reading every file takes 13.7 ms. A literal scan takes 13.1 ms, so about 10 ms faster than `rg`
  through a shell. A regex through `NSRegularExpression` takes 28.9 ms, slower than `rg` (19.6 ms). A regex through Swift's `Regex`,
  line by line, takes **173 ms**. Neither has gitignore handling, binary skipping, globs or multiline matching. **The speed case holds
  for plain literals only, and then for about 10 ms against a model call that takes seconds.**
- **What the output costs.** A very common pattern (`func `) returns 2,851 lines, 373 KB, about 93,000 tokens. ask already cuts a command's
  output at 2,000 lines or 50 KiB (about 12,800 tokens) and keeps the rest in a file; a 100-match cap would return about 3,500. The saving
  of a count cap is real, about 9,000 tokens per unbounded search, and the result stays in the context for every later request.
- **Whether models run unbounded searches.** Five natural search tasks with `gpt-6.1-sol` at low effort: three used shaped commands
  (`rg -c`, `-l`, awk counts); **two printed every match** (input tokens 20k and 10k against 8k to 14k). One model, one run each.
- **What a tool definition costs.** The eight current tools are 5,266 bytes (about 1,300 tokens) on every request; one more definition
  is about 500 to 700 bytes (about 150 tokens), so three tools add about 450 tokens per request, cached after the first.
- **Whether a sentence in the system prompt does the job.** "Keep broad searches small: count with rg -c or wc -l, and limit listings with
  rg -m or | head -100" (about 25 tokens), three runs per arm on the two unbounded-prone tasks: median input 20k to 12k on one, 23k to
  30k on the other. **INCONCLUSIVE**: the effect has the size of the noise.

## Decision

1. **No in-process `grep`, `find` or `ls` is built now.** Speed is refuted as a reason (literal only, about 10 ms; regex slower than `rg`),
   and the token saving is real but arises only for unbounded searches that ask's output cap already bounds, at a standing cost of about
   450 tokens per request.
2. **The system prompt is not changed** on this evidence.
3. **The entry stays open for the one measurable lever**: shaping what a search returns. Candidates, in order of cost: a smaller default
   cap for output that looks like a listing, a count cap when the command is a recognised search, or a `grep` tool that spawns `rg` and
   caps by match count (so its value is shape, not speed). Each needs an experiment with more than three runs and more than one model.

## Consequences

- Searches keep costing a spawn plus `rg`'s own time; nothing is added to every request.
- A model that prints every match of a common pattern still spends up to 12,800 tokens once, then carries them.
- Not established: how often real sessions run unbounded searches (five tasks, one model), whether other models bound their searches, and
  the cost on a cold cache. The rest of the sandbox-and-policy argument for a dedicated tool is untouched: the bash tool's sandbox already
  covers what `rg` reads, so no policy gap was found.
