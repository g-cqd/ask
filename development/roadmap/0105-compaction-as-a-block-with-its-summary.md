---
status: done
blocked-by: []
date: 2026-10-28
---

# 0105 — Compaction as a standard block, unfolding to its summary

Owner wish (2026-10-28 17:34): compaction should become a standard block, with duration and status, and ideally unfold to show the summary
the compaction produced.

## Today

Compaction shows as a notice line (`RunNotices.compaction(for:)` in `AgentConversation+Update`), with no duration, no running state and no
way to read what the model now sees in place of the earlier conversation.

## Plan

- A transcript item for a compaction: running (spinner and elapsed time like a tool), then done or failed, with what it replaced (turns,
  tokens before and after).
- Folded by default; unfolding shows the summary text recorded in the session's compaction entry, so a resumed session shows it too.
- A failed compaction (the summary request refused or empty) shows as failed, with the reason, instead of a notice.
- Shares the first-line and unfold behaviour of 0080, so it lands after it.

## Result (2026-10-28)

A compaction is a tool-style block, `compact · earlier messages`, so it has the spinner and elapsed time while it runs, then `N lines · ✓`
(the summary's lines) or `✗`, folded by default under `ui.tools`, opening onto the summary or, when it failed, the reason. A resumed
session shows its compactions as done blocks. The notice is gone from the screen (print mode still writes it to standard error). New
update `compactionFinished`; the status bar's `Compacting...` (0099) is unchanged. Not done: "what it replaced" (turns, tokens before and
after), which the compaction entry does not record. Tests: `CompactionBlockTests`; real binary: `Scripts/probe-compaction-block.py` (the
failed path only; the done path needs a live summary).

