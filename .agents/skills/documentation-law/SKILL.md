---
name: documentation-law
description: Write an ADR, roadmap entry or diary file in ask's required shape, and know which of the four directories a piece of writing belongs in. Use when recording a decision, planning a unit of work, writing up a session or a probe result, superseding an earlier decision, or when a doc file is about to be created, edited or split. Not for writing code, tests or README-style user documentation.
---

# The documentation law

Four directories, and the shape is enforced by tests rather than by good intentions. A journal nobody
reads to the end and a roadmap whose entries have grown into essays both fail silently, which is the one
kind of documentation defect worth a test.

Read `references/shapes.md` for a worked skeleton of each file type.

## Which directory

| The writing is… | Goes in | Because |
|---|---|---|
| A **principle** that holds regardless of what was measured | `docs/WHITE-PAPER.md` | It changes when a principle changes, and never when a probe runs |
| A **decision**, with the evidence that produced it | `docs/adr/NNNN-title.md` | One decision per file, supersession by a new record |
| A **unit of work** someone can claim and finish alone | `docs/roadmap/NNNN-title.md` | One entry per file, declaring `status:` |
| A **session**, or the **result of a probe** | `docs/diary/YYYY-MM-DD-NN.md` | The working log, capped, and where probe history lives |

The line that gets crossed most often: a probe result goes in the **diary**, never in the white paper.
The white paper once carried a table of every probe run against the project. That made the principles
document into a changelog, so it changed on almost every iteration and the principles — the only reason
anyone opens it — ended up buried under history that mattered only on the day it was written.

If you are unsure whether something is a principle or a log entry, ask whether it would still be true if
every number in it changed. If not, it is a diary entry.

## Supersede, never rewrite

A decision changed by new evidence becomes a **new ADR that supersedes the old one**:

```markdown
---
status: superseded
superseded-by: ADR-0004
date: 2026-10-18
---
```

The old record keeps its own text, with a short note at the top saying what changed and why. Editing a
record until the evidence that changed it is invisible is how decision records become useless — the next
reader cannot tell what was believed and what was merely measured.

Keep `supersedes:` on the new record as well, so the chain is walkable in both directions.

## Roadmap entries are units of work

Every entry declares a `status:` field (`not-started`, `in-progress`, `done`) and names its blockers in
`blocked-by:`. An entry is claimable and completable **alone** — if it needs two independent things, it is
two entries, and two entries in one file is a defect that a test will catch.

An entry may carry `## Done` and `## Still owed` sections. Those are not separate entries; a second
top-level `# ` title or a second `status:` field is.

Record honestly what remains owed. An entry marked done while its actual scope is unmet is worse than an
entry marked in-progress, because the next agent trusts it.

## Diaries roll over

Capped at **256 lines**. Past that nobody scrolls to the bottom to find out what happened, so a new
`YYYY-MM-DD-NN.md` starts. The ceiling is inclusive — a file at exactly 256 lines is allowed.

Append to the most recent file for the day unless it has rolled over.

## What the diary is for

The diary is written, not read. It carries the probe ledger: claim, probe, verdict. It is where the
refuted beliefs go, and those are the most valuable lines in the repository — a confident wrong belief
corrected in writing is worth more to the next agent than a correct one never questioned.

Say what you were wrong about. "This refuted us" is a useful sentence.

## Tests

The tests in `Tests/AskCoreTests` enforce the caps and the one-entry rule (`DiaryLineBudgetTests`,
`RoadmapGranularityTests`, `WhitePaperTests`), the shape of the records (`ADRLayoutTests`: a unique number, a status,
a superseded record whose successor exists and names it back) and the truth of the roadmap (`RoadmapStatusTests`:
a valid status, blockers that exist and are not already done, unique numbers). `Scripts/roadmap.sh open` prints
the roadmap from the front matter; never copy it into another document. Run
`Scripts/quality.sh --check` before committing: if you added a file that breaks the law, the suite is
what tells you, and it names the file.