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

Early. One target (`AskCore`), tested green in release. The terminal stack, the agent core and the
codemode host have not been built.

**No performance number has been measured yet.** Until
[roadmap 0004](docs/roadmap/0004-measure-the-budgets.md) lands, the performance goals are an
unmeasured claim, and nothing here may be justified by one.

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