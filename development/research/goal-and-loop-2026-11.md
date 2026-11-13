# /goal and /loop: what they should do in ask (roadmap t216, note n34)

2026-11-12. The owner (n34): `/goal MESSAGE` checks after a run whether the objective is met and goes on if not; `/loop SCHEDULE TASK`
runs a task on a schedule; both need settings bounding how much they do without the person steering. This note says what exists
elsewhere, what ask already has, and proposes the design; nothing is built.

## What exists elsewhere

Claude Code has both, documented (code.claude.com/docs/en/goal, /scheduled-tasks):

- **`/goal CONDITION`**, one per session. Setting it starts a turn with the condition as the directive. After every turn a separate
  evaluator model checks the condition against the transcript (it runs nothing itself), and either another turn starts or the goal
  clears: met, judged impossible, or a turn failed on an error the person must fix. `/goal` alone shows the condition, time running,
  turns evaluated, tokens spent and the evaluator's last reason; `/goal clear` drops it. Bounds go in the condition itself ("or stop
  after 20 turns"). Each verdict shows in the transcript, with its reason. It does not change approvals: unattended needs auto mode.
- **`/loop [INTERVAL] [PROMPT]`**, session-scoped, restored on resume, expiring after seven days. With an interval (`5m`, "every 2
  hours"; cron granularity, a minute at least) the prompt runs on that schedule; without one, the model picks the next wait (one minute
  to one hour) after each run and says why. Without a prompt, a maintenance prompt (continue unfinished work, tend the branch's pull
  request and CI, then cleanup) or the project's `loop.md`. A skill can be the prompt. Loops are listed and cancelled; one-shot
  reminders exist too. Cloud and desktop schedules are the options for work that must outlive the session.
- Both sit beside the `Stop` hook, which also fires after every turn and is the deterministic version.

## What ask already has

- **`run.stop`** (roadmap 0192): asked when a run would end with nothing queued; a hook answers `stop` or `continue(message)`, bounded
  by `hooks.maxContinues` and `maxTurns`. A goal is this point with a model as the hook.
- **Jobs** (`bash` with `yield_seconds`, the `job` tool) and **threads** (`/thread`, roadmap 0194): background work whose end is
  reported into the next message. A loop's run could be a thread, so it never blocks the person's own turns.
- **Light compaction and compaction** keep a long-running goal within the context; the status bar shows usage and cost.
- **The approval system** (0134): a goal or loop never widens what is allowed; unattended runs need the person's standing approvals.

## Proposed design

`/goal`
- `/goal CONDITION` sets it (replacing one) and starts a run with it; `/goal` shows its state as Claude Code's does; `/goal clear`.
- At `run.stop`, before hooks: a judgement request to a small model of the session's provider, given the condition, the last reply and
  the run's tool results in short, answering `met`, `not yet` with what is missing, or `impossible` with why. `not yet` continues the run
  with what is missing as the message.
- Shown: a status-bar segment `◎ goal 3/10` (turns used of the bound) and each verdict as a one-line block with its reason.
- Bounds (settings, defaults to decide): `goal.maxTurns` (10), `goal.maxCost` in the account's currency or tokens, `goal.maxDuration`
  (1 h). Reaching one stops the goal and says which. Any key the person presses during a goal's run is steering, as today.

`/loop`
- `/loop INTERVAL TASK` (`30s`, `5m`, `2h`, `every day at 9:00`), `/loop TASK` (the model picks the next wait, between bounds, and
  says why), `/loop` lists loops, `/loop stop N`. Each run is a thread, so the main conversation is never blocked, and its report
  joins the next message like a thread's.
- Kept in the session file, so they come back on resume; a loop only runs while ask is open.
- Bounds: `loop.maxRuns` (24), `loop.minInterval` (1 minute), `loop.expiry` (7 days), a cost ceiling per loop; skipped runs while one
  is still going, not stacked.

## Decisions for the owner

1. The judge: a small model of the session's provider (as Claude Code), or the session's own model?
2. The default bounds above, and whether reaching one asks the person (if present) before stopping.
3. `/loop` runs as threads (never blocking) or in the main conversation (as Claude Code's do).
4. A bare `/loop` with a maintenance prompt (branch's pull request, CI, unfinished work), and a project `loop.md` for it, or not.
5. One-shot reminders (`/loop in 20m TASK`) in the same command, or not.

## The owner's answers (2026-11-12)

1. The judge: a small model of the session's provider.
2. At a bound: ask the person when they are there, else stop.
3. `/loop` runs in the main conversation.
4. and 5. (a bare `/loop`'s maintenance prompt, one-shot reminders): not answered; left out until asked.
