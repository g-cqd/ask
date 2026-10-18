---
status: not-started
blocked-by: ["0009"]
date: 2026-10-18
---

# 0007 — Re-derive the action-to-action budget against a real action

`0004` recorded the four budgets and marked this one **provisional**. `Budget.actionToActionMilliseconds`
carries the caveat in its own doc comment, and it appears in `ECOSYSTEM.md`, `README.md` and
`Scripts/measure-budgets.py`'s own closing message.

**It measures Enter producing the next prompt in a program with no agent in it.** A trivial action, not
the one a user feels between a tool running and its result appearing.

## Why it is blocked on `0009`

This is the inversion that matters. The budget cannot be re-derived until the agent loop exists, because
the loop is what makes the action non-trivial. And the moment the loop lands, **the stale number becomes
actively misleading** — a real measurement of the wrong thing, quoted in four places, defended as if it
were the agent's number.

## Done when

- The agent loop measures a real action: a tool running and its result becoming visible.
- The number is re-derived with the same harness, same build, median and spread, never the best run.
- `Budget`'s doc comment, `ECOSYSTEM.md` and the harness message no longer describe a trivial action.
- The old figure is gone, not kept alongside. A stale number that survives its subject is worse than no
  number.

## Notes

`0004` is `done`; this is the debt it recorded. It stays `not-started` rather than `in-progress`
because there is nothing to do until `0009` lands, and a status that says "waiting" is more honest
than one that says "started".

## Also owed: the idle-memory budget

ADR-0015 measured idle RSS at 6.8 of 8 MiB after adopting AemiJSON and swift-argument-parser, about 1.1 MiB
of headroom with no agent in the binary. That budget was set over an agent-less program too, so it is
re-derived in the same pass as action-to-action, from measurements of the agent loop.

