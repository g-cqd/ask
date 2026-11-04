---
status: in-progress
blocked-by: []
date: 2026-11-03
---

# 0194 — Asides and threads: `/btw` beside the conversation, `/thread` forked beside it

The owner's idea i5 (2026-11-02): a `/btw` command to ask a question while something runs; perhaps `/thread`, a fork or subagent
thread inheriting the context, reachable from the sidebar or `/threads`. Task t191.

## The owner's choices (2026-11-03)

- **`/btw QUESTION` is a quick aside with no tools:** one extra model request, the conversation so far and the question, answered in a
  block of its own colour and never added to the conversation. It works while a turn runs.
- **Among threads, `/thread` in this process comes first:** a fork inheriting the context, with its own session file, as a lane in the
  runner tree and the sidebar, reporting back when done. Chatting with another running session (idea i8, task t196) comes after.

## Done (2026-11-03): `/btw`

- `AgentLoop.aside(_:over:)`: the request is the conversation's own (so its prefix reads from the provider's cache), with the question
  and `AgentLoop.asideInstruction` after it, in the last user message or a new one. It carries the tools' definitions, because a
  provider refuses a history of tool calls without them; only the reply's text is the answer, and a tool the model calls anyway is not
  run. Nothing is recorded in the session.
- `UsageTotals.addBeside`: the aside's tokens join the totals, while the context's size stays the conversation's last request's.
- The screen: `asideStarted` and `asideFinished` make a summary block headed `btw · QUESTION`, open (a summary ask wrote starts
  folded), its answer drawn as Markdown at full brightness, in a cyan tint of its own (`ScreenTheme.aside`, held to the same contrast
  check as the other tints). It is no part of the run: neither the run's end nor the person stopping it touches it.
- Tests: `AgentLoopAsideTests` (3), `AsideBlockTests` (2). `Scripts/probe-btw.py` through the release binary in a PTY: asked while
  the turn runs a command, answered before the turn ends, the turn then ends as it would have, the request carries the question and
  the instruction, and the session file holds no trace of it (5 checks).
- Not verified: against a real provider (the probe's server is a fake one); the colour in a real terminal.

## Still owed: `/thread`

A design first, then the owner's review: what a thread inherits (the context, the sandbox and its narrowing, the approvals granted
for the session), where its session file lives and how `/resume` shows it, what the lane shows, what "reporting back" adds to the
main conversation, and how it relates to subagents (0063) and to the jobs a thread starts.
