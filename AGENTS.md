# Working in `ask`

`ask` is a Swift terminal coding agent built for latency. Cold start, idle memory, input delay and
action-to-action delay are budgets with numbers, not adjectives.

**Read [`docs/WHITE-PAPER.md`](docs/WHITE-PAPER.md) first.** It carries the principles and leads with
the evidence rule. This file does not repeat them — it records what an agent cannot derive by reading
the source: the commands, the gates, the traps, and the decisions that are not yet settled.

## The one rule that outranks the rest

Every claim is named, given a probe that could fail, run, and recorded in the diary — before it is
acted on. This repository is full of confidently wrong beliefs that a probe overturned: DECSTR
resets private modes (it does not), `@testable` conflicts with the strict flags (it does not), Aemi's
zero tags block consumers (they do not).

Three consequences worth internalising:

- **A probe that cannot fail is not a probe.** Check the probe can fail before trusting a green result.
- **A test that has never failed proves nothing.** New gates are broken on purpose once, to prove they fire.
- **Unprobed claims are written as open questions, never as facts.**

## Commands

```sh
Scripts/quality.sh              # format, lint, build and test
Scripts/quality.sh --check      # verify only; this is what CI runs
swift test -c release --enable-testable-imports   # tests, without re-linting
python3 Scripts/measure-budgets.py .build/release/ask 12   # the four budgets
```

Build and test in **release, always**. A debug build measures a program nobody ships.

While iterating, run the tests from the existing build rather than rebuilding per edit. Build once
per completed step.

## Gates

`Scripts/quality.sh` is the only entry point, so a check cannot be forgotten because someone
remembered a different command. It runs swift-format, SwiftLint (`only_rules`), and the optimized
tests. Style is Aemi's canonical configuration, synced rather than reinvented — never re-derive
`.swift-format` or `.swiftlint.yml`.

A pre-commit hook runs lint. A green test run is not a green commit.

## Documentation law

Four directories, and the shape is enforced by tests rather than by good intentions:

| Path | Rule |
|---|---|
| `docs/WHITE-PAPER.md` | Principles, never a log. Capped at 200 lines. Probe history belongs in the diary. |
| `docs/adr/NNNN-title.md` | One decision per file. A decision changed by evidence becomes a **new ADR that supersedes** the old one — records are not edited into an unrecognisable shape. |
| `docs/roadmap/NNNN-title.md` | One entry per file, declaring `status:`. An entry is a claimable, completable unit of work. |
| `docs/diary/YYYY-MM-DD-NN.md` | The working log and **where probe history lives**. Capped at 256 lines; roll over at the ceiling. |

When a decision changes, supersede it. `status: superseded` with a `superseded-by:` link, never a
silent rewrite.

## Budgets

Four numbers, defined once in `AskCore.Budget` and printed by `ask --budgets`, so the measurement
script reads them from the binary rather than keeping a copy that can drift.

Report **median and spread, never the best run**. Percentiles, not averages. Interleave before-and-after
runs so background load cancels out of the ratio.

**Never trade correctness for speed.** `-Ounchecked` is banned: it strips the bounds and overflow checks
`StrictMemorySafety` depends on. Speed comes from doing less work.

The action-to-action budget is **provisional** — it measures a trivial action in a program with no
agent. Re-derive it when the agent loop lands, and do not let the stale number survive that change.

## Package strictness

Swift 6 language mode plus `StrictMemorySafety`, `ExistentialAny`, `InferIsolatedConformances`,
`InternalImportsByDefault`, `MemberImportVisibility`, and warnings as errors.

Do not add a flag that is not already here, and do not remove one without a probe showing the package
is better without it. `RegionBasedIsolation`, `DisableOutwardActorInference`, `InferSendableFromCaptures`
and `DeprecateApplicationMain` are deliberately absent — the compiler rejects naming them as redundant,
and `.v6` is what guarantees they stay on.

## Dependencies

Terminal stack from **TerminalKit**, kernel tier and test kit from **Aemi** at a pinned revision.
Two focused dependencies, each with one job (ADR-0005).

`Package.swift` pins TerminalKit by full revision; `Package.resolved` must agree with that revision.
After a verified upstream change, update the explicit pin and resolve it. Do not silently follow main.

Production child execution uses **swiftlang/swift-subprocess** (ADR-0011), behind an injected interface.
Introduce it with the first tool; avoid an unused dependency or a second POSIX/Foundation launcher.
Read its lifetime/output-limit contracts before implementing cancellation or output truncation.

Adding a dependency is an architectural decision. Generic tools do not live in `ask`: they are promoted
to Aemi. The test is whether a second consumer is plausible, not whether one exists today.

## Traps

- **A green old dependency is not upstream verification.** Check the explicit manifest revision and
  resolved revision together before attributing a fix to an updated package.
- **`public` signatures need `public import Foundation`** under `InternalImportsByDefault` (SE-0409).
  A plain import grants *internal* visibility, which makes `URL` internal and every public signature illegal.
- **Release tests need `--enable-testable-imports`** (ADR-0006). `swift build --build-tests -c release`
  is not equivalent and fails to resolve `@testable`. Benchmarks and shipping binaries are built
  separately, without testability.
- **Terminal behaviour needs three kinds of evidence**: byte-exact tests, an independent oracle model,
  and a real emulator. Byte tests prove the encoder emitted what was intended; they do not prove any
  terminal obeys it. Do not infer universal terminal behaviour from one emulator or from a model.

## Commit discipline

Atomic and buildable. The message states **why** — the diff already says what. Never mix a refactor
and a behaviour change. Slice by behaviour, not by file type.

A pre-existing issue found mid-task is reported as a follow-up, not silently repaired: a change that
fixes something the task did not name is harder to review, because the reviewer cannot tell the
requested change from the extra one.

## Current state

`AskCore`, `AskTUI` and the `ask` binary. The agent loop, providers and the codemode host are not built
yet. Roadmap entries under `docs/roadmap/` say what is owed; several are blocked on work landing in
TerminalKit or on Atelier's consumer switch.

Read an entry's `status:` and `blocked-by:` before starting it.