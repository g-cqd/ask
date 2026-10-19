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

## Evidence gathered by the loop (2026-10-18)

ask's own work per turn, excluding the network, is linear in history:

| Part | Fresh | After 500 turns |
|---|---|---|
| Context building | — | 204 µs |
| Request encoding | — | 1.02 ms |
| Whole loop turn | 33 µs | 210 µs |
| Barrier flush | ~0.3 ms | ~0.3 ms |

At 500 turns that is about 1.5 ms of the 2 ms budget, and the linear re-encoding would cross the budget near 700 turns. The obvious remedy is to reuse the encoded prefix of an unchanged history (a cache keyed by entry count) rather than re-encode it every turn. Decide it with the re-derived budget, on measurements.

## Idle memory, measured with the interactive screen (2026-10-19)

RSS is 8,208–8,224 KiB against the 8,192 budget; the physical footprint is 2.88 MiB. The heap is
dominated by TerminalKit's two cell grids: 393 KB at 120×40, which grow with the window (about 1.9 MB at
300×80).

The fixes already taken:
- URLSession is lazy: −3.4 MiB;
- the agent loop is built lazily: −520 KiB;
- TerminalKit's digit table went from 393 KB to 4 KB: −368 KiB.

**For the re-derivation:**
- state the window size a memory budget is measured at;
- prefer physical footprint to RSS, which counts shared library pages;
- treat TerminalKit roadmap 0007 (compact cells, ≤ 16 bytes) as the lever, not trimming ask.

## After compact cells (2026-10-19, diary 12)

TerminalKit 0007 landed. At 120×40:
- live heap 565 → 336 KB;
- footprint about 3,040 → 2,912 KiB;
- RSS about 8,632 → 8,512 KiB, still over 8,192.

The cell grids are no longer the lever; the rest is code and libraries mapped at launch. The question
for the re-derivation stands: state the window size, and decide whether RSS or footprint is the budget.
