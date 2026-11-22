---
status: in-progress
blocked-by: []
date: 2026-11-22
---

# 0239 — What work cost: tokens, money and time per turn and per task, told to the person, then to the model

The owner's note (n57 in the Sunset session, 2026-11-19; n1 here, 2026-11-21): "we could introduce in turns the information of how much
tokens/money has been spent for a turn or a task (a task of our harness, and even time for them) so that models could reuse that
information to reason a bit more about what is really valuable to work on, for how long and how, maybe this should be given to the
compaction or whatever, this needs to be refined to see how good we can make that feedback".

The research is the owner's copy of the report, `~/Public/agent-spend-feedback-report.md` (2026-11-19): vendor documents, 24 papers,
and one measurement of a session's log (98% of each prompt reread from cache: a turn's tokens mostly measure the context's size, so
the useful figure is cost per unit of work). It proposes five steps, each an experiment. **Asked**: the note. **Proposed** (by the
report, not yet refined with the owner): the steps below and their order.

## The steps (proposed)

0. **Record**, no model sees anything: per turn, tokens by kind, requests, wall time split into model time, tool time and waiting, the
   model; per task of the `tasks` tool, the same summed from `in_progress` to `done`, with its outcome. Money from a price table kept
   with ask, shown as an estimate. Checked against `ccusage` on the same log.
1. **The person sees it**: a turn's cost when it ends, a task's when it is done.
2. **The model sees a running count within a turn**, numbers or words, compared on the same tasks (the deadline study found the
   effect fragile and model-dependent).
3. **The model sees what similar past work cost** at a task's start (nobody has published this: the open part of the note).
4. **Compaction keeps a ledger** of tasks done with their cost, time and outcome, apart from the prose summary.

## Questions for the owner

- Start with steps 0 and 1 only, and decide 2 to 4 on what they show?
- Money: which price lists (subscriptions have none per token), and is an estimate in money wanted at all?
- Where a turn's and a task's cost show: the block's footer, the status line, `/tasks`, or only on request?

## Done when

Decided per step with the owner; for steps 0 and 1: the totals agree with an independent count on the same session log, and the
cost of recording is measured on the action-to-action budget.

## The owner's answers (2026-11-22)

- **Money:** tokens and time only for now. Each release of ask should carry the latest known prices, and the feedback should hold as
  much as can be known, with a comparison between two compactions. (Read as: no money on screen yet; a price table that ships with each
  release is owed, with how it is kept current still to settle.)
- **A turn's cost:** in the status line, until the next turn.
- **A task's cost:** a line when it is marked done, and beside it in `/tasks`.
- **Two tasks in progress at once:** each counts everything spent while it was open; the totals overlap.

## Step 0, built so far

- Each session entry records when it was written (`"time"`, milliseconds since 1970). A turn's wall time, its model time and its tool
  time are read from these, with no other record; an entry an older ask wrote has none.
- A turn's cost (`WorkSpend`, read from the entries after the leaf it began at): its requests, tool calls, tokens, wall time, and the
  time before each response (the model's) and each tool result (the tools', with any approval). The status line shows it until the next
  turn (`TurnSpend`). Each entry holds its response's tokens beside it (`ResponseSpend`, a reference: 8 bytes an entry rather than 80
  inline), so an entry left in the file is not read back for them.
- Left for steps 0 and 1: a task's cost from in progress to done, kept in its record, said when it is done and shown in `/tasks`; the
  comparison between two compactions; the price table that ships with each release.

