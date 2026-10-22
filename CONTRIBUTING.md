# Contributing to ask

ask is deliberately picky: claims need probes, style is not negotiable, and
the gates run whether or not anyone is watching. This page is the shortest
path to a change that survives review.

## What you need

Swift 6.4 on macOS 26 (the package's declared floor). Clone, then:

```sh
Scripts/quality.sh --check    # format, lint, release build and test — the gate
```

**CI has never run** — GitHub refuses to start the jobs for a billing reason —
so a pull request gets no machine feedback. `Scripts/quality.sh` is what CI
would run; it is the only entry point, so there is no second command to
forget. A pre-commit hook lints, and a green test run is not a green commit:
run the script.

Build and test in **release, always** ([ADR-0002](docs/adr/0002-release-only-no-testable.md)):
a debug build measures a program nobody ships. Release tests need
`--enable-testable-imports`, which `Scripts/quality.sh` passes for you.

## The evidence rule

Read [docs/WHITE-PAPER.md](docs/WHITE-PAPER.md) first. Every claim is named,
given a probe that could fail, run, and recorded in the diary
([docs/diary/](docs/diary/)) before it is acted on. Consequences:

- A probe that cannot fail is not a probe. Check that it *could* have failed
  before trusting a green result.
- Unprobed claims are written as open questions, never as facts.
- If you refute a belief — including your own — say so in the diary. A
  confident wrong belief corrected in writing is worth more than a correct one
  never questioned.

Performance numbers are reported as median and spread, never the best run, and
measured against the release binary (`Scripts/measure-budgets.py`).

## Where the rules live

| Path | What |
|---|---|
| [docs/WHITE-PAPER.md](docs/WHITE-PAPER.md) | the principles, and the evidence rule |
| [docs/adr/](docs/adr/) | one decision per file; a decision changed by evidence becomes a **new ADR that supersedes** the old one — records are never edited into an unrecognisable shape |
| [docs/roadmap/](docs/roadmap/) | one claimable unit of work per file; read an entry's `status:` and `blocked-by:` before starting it |
| [docs/diary/](docs/diary/) | the working log and the probe ledger; capped at 256 lines per file |
| [AGENTS.md](AGENTS.md) | the working discipline for agents resident in the repository (worktrees, merge flow, traps) |

## The gates you cannot see failing

These run inside `swift test`, so `Scripts/quality.sh` already enforces them:

- One top-level type per file, named for it, and a 250-line ceiling — tests
  included ([ADR-0021](docs/adr/0021-structure-is-a-gate-not-a-habit.md)).
- Banned constructs and unjustified `@unchecked Sendable` (`SourceStandards`).
- Provider names only in provider code (`AskAI/Anthropic`, `AskAI/Claude`,
  `Sources/ask`).
- The shape of ADRs, roadmap entries and diaries.
- Unused code, duplicated code and retain cycles
  ([ADR-0022](docs/adr/0022-static-analyzers-are-gates-pinned-by-version-and-hash.md));
  a finding is fixed, or accepted where it is with a written reason.

Style is Aemi's canonical swift-format and SwiftLint configuration, synced
rather than reinvented — never re-derive `.swift-format` or `.swiftlint.yml`.

## Commits

Atomic and buildable. The message states **why** — the diff already says what.
Never mix a refactor and a behaviour change; slice by behaviour, not by file
type. A pre-existing issue found mid-task is reported as a follow-up, not
silently repaired in the same commit.

## Pull requests

Small, one behaviour each. Say what was probed and what the probe showed; a PR
that claims a performance or behavioural change without a measurement will be
asked for one. If the work corresponds to a roadmap entry, name it in the PR.
