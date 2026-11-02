---
status: in-progress
blocked-by: []
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
| `request.before` | before each request | observe; `rewrite(request)` | `drive`, before `respond` |
| `response.after` | each response, recorded | observe | `drive`, after `record(.response)` |
| `tool.call` | before each call | allow; `block(reason)`; `rewrite(input)` | exists |
| `approval` | the gate would ask the person about a call | `approve`; `refuse(reason)`; `ask` (the person decides) | `ToolCallGate`, before `ask` |
| `tool.result` | after each call | `rewrite(output)`; `context` | exists, plus `context` |
| `run.stop` | the run would end: a reply without calls, no continuation of ask's own, no follow-up queued | `stop`; `continue(message)` | `drive`, after `acceptInput` finds nothing |
| `compaction.before` | a compaction starts | observe; `instructions` for the summary | `compact`, before `summarise` |
| `compaction.after` | it ended | observe | `compact` |
| `settings.change` | the model, the thinking level or the configuration changes | observe | the app, where it applies a change |
| `subagent.stop` | a subagent's run would end, once ask has subagents | as `run.stop`, for that subagent | the subagent's loop |
| `waiting` | ask waits for the person: an approval, a question, a run ended | observe | the app, where it raises these |
| `session.end` | ask quits or leaves the session | observe, with a short deadline | the app's shutdown, and `ask -p`'s exit |

How each answer works:

- **`context`** is text added to the conversation, recorded as an entry labelled by the hook, so a resumed session replays the same thing.
  The transcript shows it as a dim line with the hook's name.
- **`block` at `prompt.submit`** sends the message back to the input with the reason, as a skill that cannot load does today.
- **`rewrite`** at `prompt.submit` and `tool.call` is recorded as the rewritten form, and the transcript says that a hook changed it.
- **`rewrite(request)` at `request.before`** changes what this one request sends, for example a trimmed context. The session keeps the
  conversation as it was, and records that the hook rewrote request N and by how much, so a resume does not replay the rewrite. The
  transcript says so once per run, because it costs the provider's prompt cache.
- **`approval`** answers in the person's place: `approve` runs the call, `refuse` returns the reason to the model, and `ask` leaves it to
  the person. The first answer other than `ask` wins. It never widens the sandbox: a call the sandbox refuses stays refused. The
  transcript names the hook that answered.
- **`waiting`** is for notifications, such as a sound or a desktop banner.

## Hooks that drive the conversation: `run.stop`

`continue(message)` adds the message as a labelled user entry, and the run goes on. This is what lets a hook drive the conversation: run
the tests and send the failures back, check a list, or ask for a review pass. The guards:

- The person's follow-up comes first. `run.stop` is asked only when nothing is queued.
- The hook receives `continued`: how many times hooks have continued this run. A hook can stop itself, as Claude Code's
  `stop_hook_active` allows.
- At most `hooks.maxContinues` continues a run (a setting, default 3). Each counts against `maximumTurns`. At either limit the hook is not asked,
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
- **The sandbox.** In a narrowed session, hooks still run: none can widen the sandbox, an `approval` answer included. Tools from
  extensions are refused there (0140).
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

## Claude Code's hooks (optional)

- A setting, `hooks.claudeCode`, off by default, decides whether ask reads Claude Code's hook configuration at all.
- On, ask reads the `hooks` section of `~/.claude/settings.json`, and a project's `.claude/settings.json` and
  `.claude/settings.local.json` only once the project is trusted. It runs each command as Claude Code does: the event's JSON on stdin,
  exit code 2 blocks with stderr as the reason, and a JSON answer on stdout where Claude Code accepts one.
- Its events map onto these points: `SessionStart` → `session.start`, `UserPromptSubmit` → `prompt.submit`, `PreToolUse` →
  `tool.call` (and `approval`, through its permission decision), `PostToolUse` → `tool.result`, `Stop` → `run.stop`, `SubagentStop` →
  `subagent.stop`, `PreCompact` → `compaction.before`, `Notification` → `waiting`, `SessionEnd` → `session.end`. Tool names in its
  matchers are mapped to ask's (`Bash` → `bash`, and so on); a matcher naming a tool ask lacks matches nothing.
- Each command is a process call, with the deadlines and failure rules above.

## The owner's answers (2026-11-02)

1. Hooks may answer approvals both ways: approve and refuse.
2. Hook continues: a setting, `hooks.maxContinues`, default 3, counted against `maximumTurns`.
3. Read Claude Code's hook configuration as is, behind a setting that can turn it off.
4. Add `subagent.stop`, `settings.change`, and rewriting at `request.before`. Not a hook on every streamed event.

## Progress

- 2026-11-02: ADR-0143 records the points. `run.stop` is built: `AgentHook.runStop` and `name`, `AgentLoop.continuesByHook`,
  `AgentSettings.maximumHookContinues` (default 3), the events `hookContinued` and `hookContinuesStopped`, said in the screen and in
  `ask -p`. Tests: AgentHookRunStopTests (8), 12 mutants killed.
- 2026-11-02: the `hooks` section, the person's own file only: `hooks.maxContinues` (0 to 100, default 3) reaches
  `AgentSettings.maximumHookContinues`, and `ask config` shows it. In the catalogue, docs/configuration.md and the generated example.
  Tests: HooksConfigurationTests (6), 7 mutants killed. `hooks.claudeCode` comes with the Claude Code runner, so that it is never a
  setting that does nothing.
- 2026-11-02: the `approval` point. `AgentHook.approval` answers `approve`, `refuse(reason)` or `ask`; the loop puts the hooks
  before the person on the call's `ToolCallGate` (`first`), and the first answer other than `ask` wins. A refusal reaches the model as
  "The hook NAME refused this call: REASON"; the run says "The hook NAME allowed (or refused) this TOOL call." in the screen and in
  `ask -p`. Only calls the policy would ask about reach a hook; without a gate (`ask -p`) none does, and the sandbox's own questions are
  not approvals, so no answer widens it. Tests: AgentHookApprovalTests (6), 12 mutants killed.
- 2026-11-02: the `prompt.submit` point, for the run's first message and each queued one. `AgentHook.promptSubmit` answers `allow`,
  `block(reason)`, `rewrite(text)` or `context(text)`: rewrites chain in order, context joins after the message as `[hook NAME] TEXT`,
  and the first block keeps it out; a blank rewrite or context changes nothing. What is recorded is what was sent, so a resume replays
  it, and "The hook NAME changed this message before it was sent." is said. A blocked first message is neither recorded nor sent
  (`AgentError.promptBlocked`): the screen puts it back in the input with the reason. A blocked queued message leaves the queue
  unrecorded and goes back to the input the same way (`promptRefused`). Tests: AgentHookPromptTests (7), 19 mutants killed.
- 2026-11-02: the reference `run.stop` hook, with the owner's answers (2026-11-02): `hooks.check` names a command, from your own
  file or a trusted project's; `hooks.checkTimeout` its deadline (1 to 600 s, default 600, the `bash` tool's most). `RunStop.changed`
  says whether the run made a call that changes things (`ApprovalPolicy.changesThings`: a command, a write, an edit, input to a job)
  since its last stop or its start, read from what the session recorded. `CheckHook` runs the check only then, through the registry's
  `bash` in the session's sandbox without asking; a failure's last 8,000 characters go back as a continue, and a pass, a timeout or a
  check that cannot start ends the run. `ask config` shows the three keys. Live: with the on-device model, a run told to write 1 into
  `value.txt` was sent back by a check wanting 2, wrote 2, and ended. Tests: CheckHookTests (5), BashToolCheckTests (3), the changed
  signal in AgentHookRunStopTests (4), HooksConfigurationTests (8); 18 mutants killed.

## What is left

- The other points: `session.start`, `request.before` (and its rewrite), `response.after`, `tool.result`'s `context`,
  `compaction.before` and `after`, `settings.change`, `subagent.stop`, `waiting`, `session.end`.
- Deadlines and failing open or closed: today a hook is in-process code that ask trusts to return.
- `hooks.claudeCode`: reading Claude Code's hook configuration, with the runner for its commands.
- The check runs without showing a block while it works; only its result is said.

## Done when

An ADR records the points, `AgentHook` carries them with tests for each answer and guard (the continue limits
first), and one reference hook uses `run.stop` to send failing tests back.
