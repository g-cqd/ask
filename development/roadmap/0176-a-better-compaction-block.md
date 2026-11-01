---
status: done
blocked-by: []
date: 2026-11-01
---

# 0176 — A better compaction block

Wish (2026-11-01): "our compact block is shit as hell and should be presented in a much better way (better naming, duration of the
compaction, ...) and content should be markdown rendered."

0105 made compaction a block with its summary. What it lacks:

## The plan, as first written (the outcome follows)

- A header that says what happened in the words of other blocks (`compaction · 182k → 9k tokens`, or as decided), with its status
  and its duration in the trailing component, as tool blocks have.
- The summary drawn as Markdown (0151), folded by default like thinking.
- Interrupted and failed compactions drawn as other interrupted and failed blocks are (0142, 0162).
- Screenshots of the before and after for the owner, light and dark.

## Done (2026-11-01)

- The block is `compaction`; running, `compaction · earlier messages`; done, `compaction · 182k → 3.1k tokens`: what the summary
  request read (input, cache reads and cache writes, so a cached context counts) into what the summary is
  (`UsageTotals.compactionTokens`, from the `compacted` event's usage, which the screen used to drop). A provider that does not count
  them, and a resumed session, keep `earlier messages`.
- Opened with `ui.markdown` on, the summary is drawn as Markdown and dim (`ScreenComposer.summaryBlockLines`); its rows say they show
  lines 1 and on of the block's text, under the header at line 0, so a selection copies the summary as written. Markdown off shows it
  as written. Folded by default, as tool blocks are.
- Interrupted and failed compactions were already drawn as other blocks are (0142, 0162); a test pins the interrupted one.
- Tests: `CompactionBlockTests` (8), `UsageTotalsTests`; each new guard fails a test when removed.
- Not done: the screenshots on light and dark pages; the text rows are what the tests check.
