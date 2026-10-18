# ask

A Swift coding agent.

`ask` is a from-scratch Swift implementation of a pi-class terminal coding agent, built for latency:
cold start, idle memory, input delay, and action-to-action delay are budgets with numbers, not
adjectives.

## Read this first

**[docs/WHITE-PAPER.md](docs/WHITE-PAPER.md)** — the project rules. Paste it at the start of any
iteration. It leads with the evidence rule: every claim is challenged and backed by an actual probe
before it is adopted, and there is no place for an assumption.

## Layout

| Path | What |
|---|---|
| `docs/WHITE-PAPER.md` | The rules this project runs on, and the probe ledger |
| `docs/adr/` | One decision per file |
| `docs/roadmap/` | One entry per file — a unit of work, claimable on its own |
| `docs/diary/` | The working log, capped at 256 lines per file |

## Status

Three targets (`AskCore`, `AskTUI`, `ask`), tested green in release. The agent loop, providers, tool
execution and the codemode host have not been built — see the roadmap below.

**The four budgets are measured**, by `Scripts/measure-budgets.py` against the release binary on a PTY,
and enforced in CI. The **action-to-action** figure is provisional: it measures a trivial action in a
program with no agent in it, and must be re-derived when the agent loop lands
([roadmap 0007](docs/roadmap/0007-re-derive-the-action-budget.md)).

Read a roadmap entry's `status:` and `blocked-by:` before starting it.

## Roadmap

`docs/roadmap/` is the plan, one claimable unit of work per file. Ordered by dependency:

| Entry | Work | Blocked by |
|---|---|---|
| [0005](docs/roadmap/0005-correct-the-cross-repo-blocker.md) | Correct a blocker recorded against two repos that do not depend on each other | — |
| [0006](docs/roadmap/0006-apply-the-reset-ladder.md) | Apply the reset ladder on teardown and on signal | — |
| [0014](docs/roadmap/0014-measure-cell-pixels-and-chrome-cost.md) | Measure what a real terminal reports for its cell size, and what chrome costs | — |
| [0003](docs/roadmap/0003-probe-terminal-capabilities.md) | Probe capabilities instead of guessing from environment variables | 0014 |
| [0013](docs/roadmap/0013-adopt-the-render-pipeline.md) | Adopt TerminalKit's screen model and diff renderer | 0014 |
| [0008](docs/roadmap/0008-session-tree-and-persistence.md) | Session tree, branches, persistence | — |
| [0009](docs/roadmap/0009-the-agent-loop.md) | The agent loop | 0008 |
| [0007](docs/roadmap/0007-re-derive-the-action-budget.md) | Re-derive action-to-action against a real action | 0009 |
| [0010](docs/roadmap/0010-model-providers.md) | Model providers — first one open | 0009 |
| [0011](docs/roadmap/0011-tool-execution.md) | Tool protocol and dispatch | 0010 |
| [0012](docs/roadmap/0012-codemode-host.md) | The codemode host | 0011 |
| [0015](docs/roadmap/0015-compact-pixel-ui.md) | Compact UI drawn in pixels | 0013, 0003 |

## Building

```sh
Scripts/quality.sh            # format, lint, build and test
Scripts/quality.sh --check    # verify only; what CI runs
```

Release only, always — see [ADR-0002](docs/adr/0002-release-only-no-testable.md). A debug build
measures a program nobody ships.

Style and size are Aemi's canonical configuration, synced rather than reinvented: swift-format owns
style, SwiftLint owns size and complexity.

## Foundation

The kernel tier and the deterministic test kit come from [Aemi](https://github.com/Aemi-Studio/aemi).
The terminal stack comes from **TerminalKit**, its own repository — see
[ADR-0005](docs/adr/0005-ask-depends-on-terminalkit.md).

Aemi publishes no tags, so `ask` depends on it by pinned revision, as Atelier already does. TerminalKit
has no GitHub remote yet, which blocks a shipping dependency on it.