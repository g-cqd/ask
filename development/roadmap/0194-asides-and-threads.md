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

## The owner's choices for `/thread` (2026-11-03)

- It may do everything main may: the same tools, sandbox and session grants (two loops can then edit the same files at once).
- When it ends, its answer joins main's conversation: sent with the person's next message.
- Focusing its lane talks to it: the lane shows its conversation, and what is typed there steers it, or starts its next run.

## Done (2026-11-03): `/thread`

- `/thread TEXT` forks the session as it stands (a turn running in main: what it has written so far) into a session file of its own,
  or starts a new one before any prompt, and runs main's loop on it in this process (`AgentConversation+Threads`, `ThreadTable`). Its
  events reach the screen as `ConversationUpdate.thread(id:_:)`.
- It is a runner of the `agent` kind, listed after the jobs, `running` then `done`, `failed` or `stopped`; it stays listed once ended.
- The screen keeps each thread's conversation (`ScreenState.threads`, made with main's look by `Transcript.emptyLike`); only what a
  conversation shows applies there, never main's run or status. Its lane (`LaneView.isThread`) shows it live, its running blocks
  ticking; a message typed there goes to it (`Effect.sendToThread`) and keeps the lane, a command goes back to main.
- When a run of it ends, its last reply is shown in main as a block named after it, and is attached to the person's next message under
  `--- thread NAME ---` (`ListReferences.threadMarker`, cut from what the screen shows, as a skill's is).
- ask quitting stops the threads, as it stops the jobs.
- Tests: `ThreadLaneTests` (3). `Scripts/probe-thread.py` through the release binary in a PTY (6 checks): the thread's request carries
  main's conversation and its task; its answer is shown in main; its lane shows its conversation alone; what is typed in the lane
  continues it; main's next message takes both answers to the model; main's session holds none of the thread's words.

## Still owed

- The lane shows what the thread did, not the conversation it was forked from.
- A thread's approval questions share the screen's: one that waits when main's turn ends is declined with that turn. With
  `--allow all` none is asked.
- A thread uses main's task list and notes; the jobs it starts are not listed under it; ended threads are never removed from the list.
- Its session file is an ordinary one, which `/resume` lists without saying it is a thread.
- Memory: a second loop and conversation, not measured against the active budget; and nothing caps how many threads run.
- Not verified against a real provider, nor in a real terminal.
- After it: chatting with another running session (idea i8, task t196).
