---
status: not-started
blocked-by: ["the owner's answers below"]
date: 2026-11-02
---

# 0192 — Where hooks attach: the points, what each may do, and turns a hook starts

The owner (2026-11-02, answering 0140): extensions bring tools and hooks, "but we should first design where to put hooks (at ask's start,
before and after any turn, after a model answer with no continuation, should it allow to trigger another turn and further drive the
conversation, ...)". This entry is that design. Both routes would use it: the process host (0033) and dylibs (0140). Nothing is built.

## What exists

- `AgentHook` (ADR-0025) has two points: `toolCall`, which can allow, block or rewrite a call, and `toolResult`, which can transform a
  result. `AgentLoop.runOne` runs them in order, before the registry consults the approval gate. So a block never reaches a prompt.
- The loop (`AgentLoop.drive`) records the person's message and then repeats a cycle until the run ends:
  1. take what was offered, and compact when due;
  2. send the request (`respond`) and record the response;
  3. run the tool calls, or decide whether a reply without calls goes on (`continuesWithoutCalls`: the window filled, a drop, the
     output limit);
  4. let queued input in (`acceptInput`): steering after each response, a follow-up only when the run would finish.
- Words used here:
  - a **run** is one message from the person, up to the reply that ends it;
  - a **request** is one model call and its tool calls; a run has up to `maximumTurns` of them.

## The points

Each point says what a hook receives, what it may answer, and where it sits in the code. **Observe** means the hook sees the event and
can change nothing.

| Point | When | May answer | In the code |
|---|---|---|---|
| `session.start` | a session opens, is resumed or is switched to; after the first frame | observe; `context` | the app, when the session is chosen |
| `prompt.submit` | a message from the person enters the conversation, steering and follow-ups included, after skills, `#t3` and `@server:uri` are attached | allow; `block(reason)`; `rewrite(text)`; `context` | `drive`'s first `record(.user)`, and `acceptInput` |
| `request.before` | before each request | observe | `drive`, before `respond` |
| `response.after` | each response, recorded | observe | `drive`, after `record(.response)` |
| `tool.call` | before each call | allow; `block(reason)`; `rewrite(input)` | exists |
| `tool.result` | after each call | `rewrite(output)`; `context` | exists, plus `context` |
| `run.stop` | the run would end: a reply without calls, no continuation of ask's own, no follow-up queued | `stop`; `continue(message)` | `drive`, after `acceptInput` finds nothing |
| `compaction.before` | a compaction starts | observe; `instructions` for the summary | `compact`, before `summarise` |
| `compaction.after` | it ended | observe | `compact` |
| `waiting` | ask waits for the person: an approval, a question, a run ended | observe | the app, where it raises these |
| `session.end` | ask quits or leaves the session | observe, with a short deadline | the app's shutdown, and `ask -p`'s exit |

How each answer works:

- **`context`** is text added to the conversation, recorded as an entry labelled by the hook, so a resumed session replays the same thing.
  The transcript shows it as a dim line with the hook's name.
- **`block` at `prompt.submit`** sends the message back to the input with the reason, as a skill that cannot load does today.
- **`rewrite`** at `prompt.submit` and `tool.call` is recorded as the rewritten form, and the transcript says that a hook changed it.
- **`request.before` cannot change the request.** Changing it would break the provider's prompt cache, and the session would no longer
  record what was sent. A hook that wants something in the conversation uses `context` at another point.
- **`waiting`** is for notifications, such as a sound or a desktop banner. A hook cannot answer an approval here; see question 1.

## Hooks that drive the conversation: `run.stop`

`continue(message)` adds the message as a labelled user entry, and the run goes on. This is what lets a hook drive the conversation: run
the tests and send the failures back, check a list, or ask for a review pass. The guards:

- The person's follow-up comes first. `run.stop` is asked only when nothing is queued.
- The hook receives `continued`: how many times hooks have continued this run. A hook can stop itself, as Claude Code's
  `stop_hook_active` allows.
- At most `hooks.maxContinues` continues a run (proposed: 3). Each counts against `maximumTurns`. At either limit the hook is not asked,
  and the transcript says the limit stopped it.
- Esc stops the run as at any other point. `ask -p` honours `continue` too, within the same limits.
- When several hooks answer `continue`, their messages join, in order, into one entry, which counts as one continue.

## Rules for every point

- **Order.** User extensions run first, then the project's, each in configuration order. The first `block` wins, rewrites chain, and
  `context` texts join in order.
- **Deadlines.** Each hook declares one; the proposed default is 5 s, and 1 s for `session.end`. Past it, the hook fails as it
  declared: open (as if it allowed) or closed (as if it blocked).
  - A process hook that misses its deadline is killed.
  - A dylib hook cannot be killed. It is stopped from being called again, and the transcript says so.
- **Cost when unused.** Each point is a check of an empty list. A hook whose `match` (0140's manifest) does not cover an event is not
  called, and its extension is not loaded or started for it.
- **The sandbox.** In a narrowed session, hooks still run, since they can only block, rewrite or observe; tools from extensions are
  refused (0140).
- **Messages.** Each point is one JSON message whose name is the point, sent as `hooks/<point>` over 0033's protocol and as `call`'s
  `name` in a dylib. The answer is `{"decision": …}` with the fields above. 0033's `hooks/tool_call` and `hooks/tool_result` become
  `hooks/tool.call` and `hooks/tool.result`, since that protocol is still a draft.
- **Errors.** A hook that answers what its point does not allow, such as `continue` at `tool.call`, is treated as failed, and ask
  names it.

## Where it goes in the code

- `AgentHook` gains one method per point, each with a default that allows or does nothing, so a hook states only what it does, as now.
- The loop's points are called from `drive`, `compact` and `acceptInput`.
- `session.start`, `waiting` and `session.end` belong to the app: `AgentConversation`, the approval gate and the shutdown. Loop hooks
  and session hooks are two lists given to two owners.

## Questions for the owner

1. Should a hook be able to answer an approval: allow a call that would ask, or answer for the person? Or only block and rewrite, as
   proposed?
2. Is 3 the right number of hook continues per run, and should they count against `maximumTurns`?
3. Accept Claude Code's hook configuration as well? Claude Code runs a command with the event's JSON on stdin, and exit code 2 means
   block. Its points map onto these: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `PreCompact`,
   `Notification`, `SessionEnd`. Existing hooks would then work unchanged, at a process's cost per call.
4. Anything missing? Candidates: a hook on each streamed event (only a dylib could afford it), and `subagent.stop` once ask has
   subagents.

## Done when

The owner has answered, an ADR records the points, `AgentHook` carries them with tests for each answer and guard (the continue limits
first), and one reference hook uses `run.stop` to send failing tests back.
