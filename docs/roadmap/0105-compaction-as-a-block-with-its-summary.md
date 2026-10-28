---
status: not-started
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
