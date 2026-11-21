---
status: not-started
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
