# Worked shapes

Skeletons to copy. Each is the real frontmatter shape used in this repository.

## An ADR

```markdown
---
status: accepted
supersedes: ADR-0004
date: 2026-10-18
---

# 0007 — The title states the decision, not the topic

## Context

What was believed, and what made the question worth asking. Name the constraint that forced a choice.

## The probes

Each claim, the probe that tested it, and the verdict — CONFIRMED, REFUTED, or INCONCLUSIVE. This is
where a decision earns its authority. A reader who skips to "Decision" without reading these cannot tell
a measured decision from a confident guess.

## Decision

The decision, in the present tense, numbered if it has parts.

## Consequences

What this costs, what it makes easier, and what is now owed. Consequences that are uncomfortable belong
here rather than being left out — a consequence nobody mentions is the one that surprises somebody later.
```

Superseded records set `status: superseded` and add `superseded-by:`, and keep their original text
under a short note explaining what the new evidence was.

## A roadmap entry

```markdown
---
status: in-progress
blocked-by: ["0001"]
date: 2026-10-18
prerequisites: ["ADR-0005"]
---

# 0002 — The title names the work

One or two paragraphs: what the work is, and why it is worth doing.

## Done

What actually landed, with commit references where they exist.

## Still owed

What remains, stated concretely enough that the next agent can start without re-deriving the problem.
```

`status:` and `blocked-by:` are what make an entry claimable. Keep them accurate — a stale
`blocked-by` sends someone to wait on work that already landed.

## A diary file

```markdown
# Diary — 2026-10-18 (06)

## What happened

The session's narrative, in the order it actually happened.

## The probes

| # | Claim | Probe | Verdict |
|---|---|---|---|
| 23 | TerminalKit `main` renames a symbol `ask` uses | `swift package update terminalkit` in a scratch copy, then build | **REFUTED** — 8 sites fail. The lockfile was stale. |

## Still owed, and not to be assumed

The things a future session could easily mistake for done.
```

The table only ever grows, and it grows only with probes that actually ran. It is never consulted to
decide what the principles are.

## Length discipline

| File | Cap | Enforced by |
|---|---|---|
| `docs/WHITE-PAPER.md` | 200 lines | `WhitePaperTests` |
| `docs/diary/*.md` | 256 lines | `DiaryLineBudgetTests` |
| ADR / roadmap entry | one decision, one entry | `RoadmapGranularityTests` |

When a diary hits the cap, start `YYYY-MM-DD-(NN+1).md`. Do not trim history to fit — the cap exists so
files roll over, not so entries get dropped.