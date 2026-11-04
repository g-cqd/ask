---
status: not-started
blocked-by: []
date: 2026-11-04
---

# 0195 — Threads merge into their parent: a summary, after everything below them settles

Threads, part 2 (task t205; notes n15, n16 and n17). 0194 built `/thread`: a fork of the conversation run beside it, whose last reply
goes to main with the person's next message. The owner wants it to work like branching out and merging back in. This entry records the
owner's answers of 2026-11-04 and proposes the rest: the lifecycle, what is recorded, the settings, and what the owner had not asked
about. Nothing here is built yet.

## The owner's answers (2026-11-04)

- **Merge into the parent, as a summary.** A thread merges into the conversation it was forked from: main, or the thread above it.
  It sends a summary, made by one more request "a bit like a compaction", not its last reply.
- **Merging waits.** A thread does not merge while it is waiting on an approval or a question. Its ancestors wait too, all the way
  up. A parent also waits for any child that has not merged yet, including a child that is still running (answer 1: yes).
- **A stopped thread needs the person's confirmation to merge back in** (answer 2).
- **Quitting with threads unmerged:** they are recorded as unmerged, shown on `/resume`, and not restarted (answer 3: yes).
- **Resume lives in threads.** `/resume` itself lists main sessions. Inside a session, a thread can be continued from its lane only
  while it is unmerged; a merged thread cannot be.
- **Shown in the parent:** a merge appears as a system block in the parent, folded, which opens onto the thread's summary.
- **Jobs go in the tree by default,** under the thread that started them.
- **Names from the on-device model by default,** and that can be turned off.

## The owner's notes of the afternoon (2026-11-04, n19 to n23)

- **Where a thread starts is shown in its parent (n23),** prominently: a block of its own kind in the parent's conversation, at the
  fork point. It carries the thread's name, its state and its prompt, and a click opens the thread's lane. When the thread merges, its
  merge block (folded, opening onto the summary) comes later in the parent. The two can name each other ("started here", "merged
  from here").
- **Naming may use any model the person chooses (n20):** the on-device model, or a provider and model from the configuration. See
  `threads.names` below.
- **Without room for the sidebar, the tree goes below the input (n21).** The strip under the input shows the same tree as the
  sidebar: threads under main, with their jobs under them. Today it lists runners with indentation only.
- **The strip leaves merged threads out (n22).** They are found through `/threads`, a picker with search over every thread of the
  session, merged or not. Merged threads also expire from the sidebar after `threads.mergedShownFor`, and stay reachable through
  `/threads`.
- **Where a question pops up (n19)** is a setting, for threads as for subagents. It can appear at once in whatever the person is
  looking at, after a delay if they have not gone to it, or never, so they go to the thread themselves. See `threads.questions` below.
- **Subagents build on threads (n19; roadmap 0063).** The difference is in what they inherit and who starts them:
  - The parent's model spawns them, not the person.
  - They get an explicit request, not the whole conversation.
  - They run as a defined agent (the person's or the workspace's), or without one.
  - They always merge on their own.
  - A parent waiting on a subagent that is waiting on the person stays live, holding its request, as the waiting rule above says.
    Requests should be explicit enough that such questions are rare.

## The lifecycle

| State | Meaning | Sidebar mark | Lane input |
| --- | --- | --- | --- |
| working | a request or a tool is running | spinner | steers it |
| waiting | an approval or a question waits on the person | `?` | answers it |
| idle | its run ended; not merged yet (something below it holds it, or merging is `ask`) | `○` | continues it (a new run) |
| held | idle, and a descendant is not merged yet | `◌` and "waiting on NAME" | continues it |
| merging | its summary request is running | spinner, dim | read-only |
| merged | its summary reached its parent; closed | `✓`, dim | read-only; `/thread` branches from it |
| stopped | the person stopped it | `■` | asks: merge back in, or keep it unmerged |
| failed | its run failed | `✗` | as stopped |

The rules:

- A thread is **ready** when its run has ended and every child has merged.
- A ready thread merges on its own (`threads.merge: "auto"`) or after a question (`"ask"`).
- Merging runs the summary request on the thread's own context, as compaction does, so the provider reads it from cache.
  `Compaction.summaryResponse(for:instruction:)` already does this; it needs a merge instruction.
- The summary becomes a `.threadMerged` entry in the parent's session:
  - For main, it goes with the person's next message, as 0194's report does now.
  - For a parent that is itself waiting to merge, it goes into that parent's context before its own summary request. A summary
    therefore carries what its children merged into it, and merges move up the tree from the bottom.
- Main never waits for anything.
- Stopping a thread stops its descendants first. The confirmation then asks once for all of them: "Merge thread-1 and its 2 threads
  back in?"
  - Yes: each merges, bottom up, with a summary that says it was stopped.
  - No: they stay unmerged, and can be continued or merged later from their lanes.

## Approvals belong to the thread

Today every loop asks through the one sink of main's current run (`Approvals.ask`). A thread's question is therefore declined when
main's turn ends, which 0194 lists as owed. Each thread needs its own sink:

- The question is drawn in the thread's lane.
- Its sidebar row shows `?`.
- The status line counts it ("1 waiting").
- Nothing declines it except the person, or stopping that thread.

Session grants stay shared, because the owner chose "everything main may do". A grant given in a thread therefore holds for main too.
That needs saying in the question ("Allow for this session (main and its threads)").

## What is recorded

Main's session file gains three records, of `type: "thread"`:

- `.threadStarted`: the id, name, parent, prompt, the thread's session file, and the entry it was forked at;
- `.threadRenamed`;
- `.threadMerged`: the id and the summary.

The thread's own session file says it is a thread: its parent session and its id.

- `/resume` leaves thread files out of its list.
- Resuming main rebuilds the tree from these entries.
- Merged threads come back read-only, with their conversation readable in their lanes.
- An unmerged thread comes back idle, not running. Typing in its lane continues it; that is the only resume there is.
- **Compatibility (the owner, 2026-11-04; ADR-0144).** The format version stays 2. The thread facts are records of `type:
  "thread"`, outside the conversation tree. An ask from ADR-0144 on keeps a record or entry it does not know, byte for byte, without
  reading it or calling it damage. Older files are converted by migration steps, which are removed before 1.0.0-rc.1 (roadmap 0070).

## Names

At start, the on-device model (`AskApple`, where `SystemLanguageModel` is available) is given the thread's prompt and asked for a name
of two to four words, such as "parser error recovery".

- The id stays `thread-N`, so reports, files and keys stay stable; the name is what is shown.
- With no on-device model (an older Mac, Linux, or Apple Intelligence turned off), or when it fails or takes more than about a
  second, the name is `thread-N` and nothing is said.
- `/rename NAME` in a thread's lane renames it. In main, `/rename` would name the session; that is worth having, but it is not in this
  entry.

## Jobs in the tree

A job does not know which loop started it. The tool context has to carry the thread's id into the job table, which then gives the job
its `parentID`. The sidebar already places a runner under its parent (0194); jobs from main sit under `◆ main`.

`ui.sidebar.jobs: "section"` keeps today's separate Jobs section. Note n15 asked for a key as well:

- In the sidebar, letter keys go to the input, so I propose `/sidebar jobs` to switch between the two for this run, rather than a new
  key.
- A key can be added once the sidebar can take keyboard focus of its own, which the resizing work in t202 would need too.

Marks distinguish the kinds: `◆` main, `◇` a thread when it is not running, `$` a job when it is not running. A running runner of
either kind shows its spinner.

## Settings proposed

| Setting | Values (default first) | Why |
| --- | --- | --- |
| `threads.merge` | `"auto"`, `"ask"` | whether a ready thread merges on its own |
| `threads.names` | `"onDevice"`, `"numbered"`, or a model (`"provider/model"`) | how a thread is named (n20) |
| `threads.questions` | `"focus"`, `"after"`, `"never"` | where a thread's approval or question appears: at once in whatever is shown, after `threads.questionsAfter`, or only in its lane (n19) |
| `threads.questionsAfter` | `"30s"` | the delay `"after"` waits before showing the question where the person is |
| `threads.mergedShownFor` | `"1d"`, a duration or `"always"` | how long a merged thread stays in the sidebar; `/threads` finds it after that (n22) |
| `threads.max` | `4`, 1 to 16 | running threads at once; 0194 owes a cap and a memory measure |
| `threads.depth` | `3`, 1 to 8 | how deep `/thread` may nest |
| `threads.model` | the session's model | a cheaper or faster model for threads |
| `threads.summaryInstructions` | none | added to the merge instruction, as `compaction.before` hooks add to compaction's |
| `ui.sidebar.jobs` | `"tree"`, `"section"` | where jobs go (n15) |
| `ui.sidebar.merged` | `"tree"`, `"section"`, `"hidden"` | where merged threads go: dim in the tree (the owner agreed, 2026-11-04), in their own section, or not listed |

There would also be two hook points for 0192: `thread.start` (refuse a thread, or rewrite its prompt) and `thread.merge` (add to the
summary instructions, or rewrite the summary).

## What the owner did not ask about, worth deciding

1. **Two loops editing the same files.** Threads share the working tree, so a thread and main can change one file at once. The
   branching analogy points at a stronger option, `threads.isolation: "worktree"`: each thread in a git worktree of its own, whose
   merge offers its changes back as a diff to apply. That is large, and depends on 0186's git work. Until then the summary should list
   the files a thread changed, so the parent knows.
2. **When a summary arrives while main's turn runs.** It goes with the next message (today's behaviour), or steers the running turn,
   as a queued message can. A possible setting: `threads.deliver: "nextMessage"`, `"steer"`.
3. **Telling the person.** A thread waiting on them while they are in main shows only as a count on the status line. A terminal
   notification (OSC 9 or 777, which TerminalKit would need) or a bell could follow, as `ui.notify`.
4. **`/new` and `/resume` with threads running.** These should ask first: stop them (recorded unmerged), or stay.
5. **Cost.** Each thread's tokens counted in its lane and its sidebar row, and in the total. Perhaps a per-thread token limit later.
6. **Compaction inside a long thread.** It works as in main, and the merge summary reads the compacted context. Nothing new, but it
   needs testing.
7. **Tasks and notes.** A thread uses main's task list (0194 owes this). Its tasks could carry the thread's name, so the list says
   which branch did what.
8. **`/threads`.** The owner's first idea (i5) named it. It is now the way to find merged threads (n22): a picker of the whole tree,
   with search over names and prompts.

## Done (2026-11-04): step 1, approvals and questions belong to the thread

- `ApprovalRoute`, task-local, is set by a thread's run: every approval and model question asked inside it goes to that thread
  (`.thread(id:, .askApproval)`, `.askQuestions`) instead of main's current run, and its runner is listed as waiting for approval
  while any of its questions waits (`ThreadTable.asking`).
- The screen keeps each thread's questions with its conversation (`ThreadView`); its lane shows them and takes their keys; main's
  run ending no longer clears them. In a thread's lane, main's own questions wait in the lane and the status says "Main is waiting
  for an answer"; leaving puts them back. A thread's run ending takes away only what it still asked.
- `ThreadQuestionsTests` (4); `Scripts/probe-thread-approval.py` (5 checks, approvals on, the release binary in a PTY): main never
  shows the thread's question, the thread stays waiting after main's turn ended, its lane shows it, answering there runs the command.
- Not done yet: the `threads.questions` setting (focus, after, never); today a thread's question shows only in its lane, and the
  sidebar's `?` and the counts say it waits.

## Done (2026-11-04): step 2, merging into the parent

- A thread whose run ended merges once every thread under it has merged; until then it is `held` ("waiting on its threads"). The
  merge is one more request, `AgentLoop.aside(_:over:instruction:)` with `AgentLoop.mergeInstruction`, over the thread's own context
  (so read from the provider's cache), carrying the summaries merged into it. A failed request sends its last reply instead.
- The summary goes to its parent: main's next message, or the parent thread's next message and its own summary. Merges go from the
  bottom up: the last child to merge settles its parent (`AgentConversation+Merge`, `ThreadTable`).
- A thread that failed or was stopped asks in its lane whether to merge it back in; no keeps it unmerged. Nothing is asked or merged
  while ask quits.
- A merged thread is read-only: typing in its lane says so; `/thread` there still branches from it.
- The parent shows where the thread started (`ConversationUpdate.threadStarted`: an open block in the aside's colour, note n23) and
  where it merged (`threadMerged`: folded, opening onto the summary). New runner states `held`, `merging`, `merged`; the sidebar marks
  them `◌`, a spinner and a dim `✓`.
- `ThreadBlocksTests` (3); `probe-thread.py` rewritten for the lifecycle (9 checks: the fork block; a nested thread; the outer thread
  held while the inner one sleeps; the inner one's summary request, then the outer one's carrying it; read-only after merging; main's
  folded merge block; main's next message carrying the outer summary with the inner inside; main's session clean).
  `probe-thread-approval.py` 5, `probe-sidebar.py` 14.
- Not probed: the failed-or-stopped confirmation (no fake-provider failure in the probes yet), and stopping one thread from the screen,
  which does not exist yet (only quitting stops threads).

## Done (2026-11-04): step 3, first part, ADR-0144's groundwork

- A line of a record type this build does not know is kept in the tree (`SessionTree.unknownRecords`) and written back by a rewrite;
  an entry of a kind it does not know is `SessionPayload.unrecognized(kind:line:)`: in the tree, its children hanging from it,
  skipped by the request context, the replay and compaction, and written back as its line. Neither is an issue. A line that is no
  record, or a known kind that is broken, is still damage (`SessionLogProbe` tells them apart).
- `SessionMigration` (`Sources/AskAgentCore/Session/Migrations/`): the steps an older file opens through, each marked
  `removeBefore: "1.0.0-rc.1"`; the format 1 upgrade is the first, and decides which versions open.
- `SessionUnknownTests` (4), `SessionMigrationTests` (2); two tests that held the old rule now hold ADR-0144's. Every suite passes in
  debug; the release tests are CI's.

## Done (2026-11-04): step 3, threads kept with the session

- Records of `type: "thread"` (`ThreadRecord`, `SessionLogRecord.thread`, `SessionTree.threads`), outside the conversation: in
  main's session, `started` (id, parent, prompt, its session file, `at`: the leaf of where it was forked from) and `merged`
  (summary, `at`: the leaf of where it merged); in a thread's own session, `identity` (whose it is).
- A resume (startup `--continue` or `--resume`, `/resume`) rebuilds the tree (`restoreThreads`): the table is emptied, stopping what
  the previous session ran; each started thread's session is opened; merged ones come back read-only, the others `stopped`, never
  restarted, continuing when something is typed in their lane. Each lane replays its own conversation from its fork point; main's
  history and each lane place the fork and merge blocks after the entries they name, in the order they happened.
- `/resume`, `ask sessions` and `--continue` leave threads' sessions out (`SessionSummary.isThread`). Before this, `--continue`
  reopened the newest file, a thread's, as the conversation (found by the probe).
- A run stopped by a session switch no longer touches the thread that took its name (`ThreadTable.owns`). The screen drops the
  conversations of threads no longer listed.
- `ThreadRecordTests` (2); `Scripts/probe-thread-resume.py` (8 checks, two processes): the blocks in place after `--continue`, merged
  and stopped come back as such, the merged lane read-only, the stopped one continued from its own conversation and merged, and
  `/resume` listing main's session only. `probe-thread.py` 9, `probe-thread-approval.py` 5, `probe-sidebar.py` 14.
- Not done: a thread started before main has a session is not recorded (main has no file yet); `/new` and `/resume` with threads
  running stop them without asking; where a child merged into a parent thread, the block goes after the parent's leaf then, which
  may come before its later replies.

## Done (2026-11-04): `/reload` with a thread's lane shown (the owner's request)

- `/reload` typed in a thread's lane keeps the lane. The screen tells the conversation which lane is shown (`Conversation.laneShown`);
  `reExecute` passes it as `--focus-thread`, and the new process ends its opening updates with `.focusThread`, which opens that lane
  again, drawn from the thread's session.
- `ThreadLaneTests`; `Scripts/probe-thread-reload.py` (3 checks, a real `/reload` of an installed build), twice.

## Done (2026-11-04): stopping, switching, and the fork block's click

- Ctrl+C in a working thread's lane stops it and every thread under it (main's turn goes on), then asks once, in its lane, whether
  to merge them back in: yes merges them from the bottom up, no leaves them stopped and unmerged (`stopThread`, `ThreadTable.subtree`,
  threads held together are not settled one by one). A confirmation starts on No.
- `/new`, `/resume` and `/fork` with threads at work ask first; yes stops them, left unmerged in the session they belong to. Threads
  are asked about before the "jobs are running" refusal, since a thread's running command is listed as a job and stopping the thread
  ends it.
- A thread started before any prompt creates main's session first, so it is recorded.
- A click on where a thread started opens its lane (note n23; `Transcript.forkBlocks`).
- `ThreadBlocksTests` (+2); `Scripts/probe-thread-stop.py` (7 checks), twice.
- Also: `ScreenSession.swift` and `Ask.swift` had passed the 250-line ceiling with the `/reload` change (86af8e14, the rule tests not
  run before landing it); split into `ScreenSession+Run.swift` and `Ask+Request.swift`.

## Done (2026-11-04): a thread's jobs are listed under it

- `JobOwner.current` (AskTools, task-local) is set by a thread's run; the job table keeps each job's owner and lists it
  (`JobSummary.owner`), and the job's runner has the thread as its parent. The sidebar and the list under the input show it under
  the thread.
- `ui.sidebarJobs` (`"tree"`, the default, or `"section"`, every job in the Jobs section), and `/sidebar jobs` to switch it for the
  run. In section mode the runner tree drops the jobs' parents, so the keys move in the order drawn.
- `SidebarJobsTests` (3); `probe-thread-stop.py` checks the thread's command listed under it (8 checks).

## Done (2026-11-04): limits, names, `/rename`, `/threads`

- The `threads` section (`ThreadsSection`): `max` (default 4, 1 to 16) and `depth` (default 3, 1 to 8), checked when a thread would
  start, depth first; `names`, `"onDevice"` (the default) or `"numbered"`. A project's file may set them: they only limit.
- On-device names (`ThreadNamer`): two to four words from the task, from Apple's on-device model where it is available, given two
  seconds; the id stays `thread-N`, and the name is what is listed.
- `/rename TITLE` in a thread's lane names it. Names are recorded (`ThreadRecord.renamed`) and come back with a resume.
- `/threads` lists the session's threads, merged or not, by name, state and task; choosing one, or `/threads NAME`, shows its lane.
  Its rows go stale whenever the runners change.
- Probes set `threads.names` to `"numbered"`, so the on-device model never makes them depend on its answer.
- `ThreadRecordTests`, `ThreadLaneTests`; `Scripts/probe-thread-names.py` (6 checks, two processes), three times.
- Not done: naming with a chosen provider model (n20), `threads.questions` (n19), `threads.mergedShownFor` and the strip's leaving out
  merged threads (n22), `threads.merge: "ask"`, `threads.model`, `threads.summaryInstructions`, the hook points, distinct marks and
  idle spinners (n15), and active memory with several threads measured.

## Done (2026-11-04): one list at a time, flat for jobs, a tree with threads (the owner's steer)

- While the sidebar is shown (open, and the screen wide enough) the list under the input is not drawn, a lane included: the sidebar
  is the list and the way back. `/jobs` then says the sidebar lists them. Neither is shown by default.
- The list under the input is flat while there are only jobs; once a thread exists it is the sidebar's tree (`SidebarEntries`,
  without the empty row before Jobs), windowed to its rows. In a lane its main row reads `◆ main  back to the conversation`.
- `RunnerListShapeTests` (3); the strip tests now hold the tree; the probes read the list through `Scripts/probe_runner_list.py`
  (rows under the status line, a runner's state from its mark). All thread probes and `probe-sidebar.py` pass.
- pyte left the list's old rows on screen after a session switch until a full repaint (it does not scroll regions); not checked in a
  real terminal.

## Done (2026-11-04): `/merge` (and `/close`)

- Nothing else merges a thread stopped and not merged back, or one a resume brought back stopped. `/merge` in its lane merges it now,
  with the unmerged threads under it, from the bottom up, as a yes to the stop's question does (`mergeTogether`, shared). Refused while
  any of them works, waits on the person or merges, with how to stop it. `/close` is the same command: merged is closed, read-only.
- Test first: `ThreadLaneTests` (red: the command went back to main), then `Scripts/probe-thread-merge.py` (red: no refusal, nothing
  merged), then the code; 4 checks, twice.

## The order to build it

1. ~~Thread-owned approvals and questions.~~ Done, above.
2. ~~The lifecycle and the waiting rule, merge by summary into the parent, and the system block.~~ Done, above; the stop with its
   confirmation is not probed.
3. ~~ADR-0144 first: unknown records and entries kept, and the migration steps. Then the thread records, and resume rebuilding the
   tree.~~ Done, above.
4. Jobs parented to their thread, and the two sidebar settings.
5. The fork-point block (n23), the tree under the input (n21) and `/threads` (n22).
6. Names: on-device or a chosen model, `/rename`, `threads.names`.
7. The caps: `threads.max` and `threads.depth`, with active memory measured against the 25 MiB budget.
8. Then subagents (0063), on the same lifecycle.

Each step is probed through the release binary in a PTY, as `probe-thread.py` does.
