---
status: done
blocked-by: []
date: 2026-10-29
---

# 0138 — The context repair notice came back before every turn

Owner (2026-10-29): "Repaired the context before this turn: [AskAgentCore.RequestContext.Repair.interruptedToolCall(id: …)]" — "i have that issue
coming back again and again".

## Cause

The request is rebuilt from the session log for every request (`RequestContext`). A stop between two tool calls of one response recorded the
first call's result and left the second unanswered (`runTurn` threw at its cancellation check, and a test pinned that). Every later request then
needed the same repair, an error result standing in for the missing one, and reported it, and the notice printed the Swift value.

## Fix

- A stop records each call the turn never started as `Not run: the turn was stopped before this tool started.` (`AgentLoop.notRunResult`), so the
  log answers every call it holds and the next request needs no repair. The tool really did not run; the record says that and nothing more.
- A session already damaged (by an older ask, or a crash) is still repaired before every request, but the loop reports each repair once
  (`ReportedRepairs`, shared by reference like `LearnedWindow`); a reload reports it once more.
- The notice is in words: `Repaired the context: a tool call with no result was answered as interrupted.` (`RequestContext.describe`), in the screen
  and in print mode.

Tests: the abort test now expects the not-run result and no repair; `RepairReportTests`; a loop test that runs two turns on a damaged session and
sees one report. Not run against the owner's live session before the reload.
