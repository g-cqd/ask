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

## Done (2026-11-04): the sidebar, by the owner's request

The owner: the sidebar "isn't well presented", "the background colouring of the session blocks is leaking into the sidebar", it should
show "the tree of threads and another section for the jobs", "more compact".

- A tinted block's row was filled to the screen's edge and the sidebar written over it, so the tint showed through every cell the
  sidebar's text did not cover. A row is now tinted to the divider; the panel is blanked first (`ScreenComposer.write`). Pinned by
  `SidebarSectionsTests` (fails on the old code) and `probe-sidebar.py`'s check on the real terminal's cells.
- Two sections (`SidebarEntries`): Threads, a tree with box-drawing guides under a `◆ main` row (also the way back from a lane), and
  Jobs. A runner belongs to its root's section, so a job a thread started stays under the thread. Empty sections are left out; with
  nothing, "No threads or jobs".
- One row per runner: a state mark instead of a trailing word, the name (a job's without its brackets), what it does, and an active
  one's duration at the right edge; ended rows dim, the lane shown bold, the keyboard's choice inverse. The panel is 22 to 36 columns.
- `RunnerTree` puts thread roots before job roots, so Up and Down move in the order drawn, in the strip as in the sidebar.
- The status counts both: `1 thread · 2 jobs`.
- `/thread` typed in a thread's lane forks that thread (`Effect.startThread(from:text:)`), listed under it; its notices go to that
  lane. Its answer still goes to main, as every thread's does.
- `probe-thread.py` 7 checks, `probe-sidebar.py` 12 checks, through the release binary in a PTY.

## Done (2026-11-04): a steadier sidebar (note n24, task t207)

- Its first row holds only a toggle in the screen's top-right corner: `»` closes it; closed, `«` stays in that corner cell (on the
  top row's own background) and a click opens it. The closed corner is a pointer target of its own, above the transcript's.
- `◆ main` is always listed; the "Threads" heading is gone, main being the tree's root. The Jobs heading has no count.
- The last row counts what is running and what waits ("1 thread, 2 jobs running · 1 waiting"; "3 running" when that does not fit;
  "Nothing running").
- `SidebarTests`, `SidebarSectionsTests`, `HoverTests`; `probe-sidebar.py` 14 checks through the release binary.

## Still owed

- The lane shows what the thread did, not the conversation it was forked from.
- ~~A thread's approval questions share the screen's.~~ Done in 0195, step 1: they are the thread's own.
- A thread uses main's task list and notes; the jobs it starts are not yet given it as their parent (the sidebar would list them under
  it); ended threads are never removed from the list.
- A nested thread's answer goes to main, not to the thread it was forked from.
- Its session file is an ordinary one, which `/resume` lists without saying it is a thread.
- Memory: a second loop and conversation, not measured against the active budget; and nothing caps how many threads run.
- Not verified against a real provider, nor in a real terminal.
- After it: chatting with another running session (idea i8, task t196).
