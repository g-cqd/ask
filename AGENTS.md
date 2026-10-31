# Working in `ask`

`ask` is a Swift terminal coding agent built for latency. Cold start, idle memory, input delay and
action-to-action delay are budgets with numbers, not adjectives.

**Read [`development/WHITE-PAPER.md`](development/WHITE-PAPER.md) first.** It carries the principles and leads with
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

## Reliability

Damage costs only what is actually damaged. Everything intact loads, every repair is reported, and reading
never writes; `SessionLog.recover` is the worked example (ADR-0013). Refusing input needs a written safety
reason. Convenience is a requirement, not a nice-to-have.

Code and tests state their own reasons. When studying another agent, run its code against edge cases
rather than trusting its source, and keep the notes in `development/research/`, not in the codebase.

## Commands

```sh
Scripts/quality.sh              # format, lint, build and test
Scripts/quality.sh --check      # verify only; what CI would run (it has never started: billing, roadmap 0028)
Scripts/analyzers.sh            # unused code, duplicated code, retain cycles; also a stage of quality.sh
Scripts/mutate-changed.sh       # mutation testing of the Sources files changed against origin/main; no new survivor allowed
Scripts/dependency-audit.sh     # each target declares what it imports and imports what it declares; a stage of quality.sh
python3 Scripts/check-layers.py # ADR-0009's target layering over the manifest; a stage of quality.sh
Scripts/roadmap.sh open         # the open roadmap entries, read from their front matter
ask --provider NAME --model ID  # a provider from ~/.config/ask/providers.json (ADR-0027)
swift test -c release --enable-testable-imports   # tests, without re-linting
python3 Scripts/measure-budgets.py .build/release/ask 12   # the four budgets
python3 Scripts/measure-action.py .build/release/ask 10 500  # the action, in detail, after 500 turns
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

**Structure is gated too (ADR-0021).** `SourceStructureTests` and `ProviderNeutralityTests` run inside
`swift test`, so the pre-push hook and `quality.sh` enforce them (CI would, if it ran): one top-level type per file, named for it;
no file over 250 lines, tests included; provider names only in `AskAI/Anthropic`, `AskAI/Claude` and
`Sources/ask`. Read the `ask-structure` skill before adding or moving code. `SourceStructure.knownViolations`
is a ratchet baseline: it shrinks and never takes a new entry.

**Static analysis is gated too (ADR-0022).** deadwood, dolly and arcleak run under `--strict`, pinned by version
and SHA-256 in the family's lock, `Scripts/analyzers.lock` in Aemi-Studio/aemi at the commit `Scripts/analyzers.sh` names. A finding is fixed, or accepted where it is with a reason
(`// @dl:accept -- why`, `@dw:`, `@al:`, on the line above the anchor); there are no baselines.

**Mutation testing, on changed files (roadmap 0166).** `Scripts/mutate-changed.sh [BASE]` runs swift-mutation-testing (pinned by version
and SHA-256 in the script) on the `Sources` files changed against `BASE`, each with its target's tests, and fails on a surviving mutant
not in `development/mutation-baseline.json`: kill it with a test. Minutes per file cold, seconds once its verdicts are cached; before
a commit that changes logic, run it. `ASK_MUTATE=1 git push` runs it as a pre-push task; CI runs it on pushes that touch `Sources`,
and weekly on every file, uploading a fresh baseline.

**When a refactor or factorisation is on the table, ask what Swift already offers first** (white paper §8):
result builders, scoped closures, protocol extensions with defaults, typed throws, `callAsFunction`, key paths,
macros. Compile candidates, pin behaviour with a characterisation test, benchmark on a request path.

The pre-push hook runs `.project-hooks.yml`'s release task, not a plain `swift test`. If a hook looks wrong,
`project-hooks repair --dry-run` says whether it is the generator's current script.

## Documentation law

Four directories, and the shape is enforced by tests rather than by good intentions:

| Path | Rule |
|---|---|
| `development/WHITE-PAPER.md` | Principles, never a log. Capped at 200 lines. Probe history belongs in the diary. |
| `development/adr/NNNN-title.md` | One decision per file. A decision changed by evidence becomes a **new ADR that supersedes** the old one — records are not edited into an unrecognisable shape. |
| `development/roadmap/NNNN-title.md` | One entry per file, declaring `status:`. An entry is a claimable, completable unit of work. |
| `development/diary/YYYY-MM-DD-NN.md` | The working log and **where probe history lives**. Capped at 256 lines; roll over at the ceiling. |

`docs/` is not a record: it is the user guide, written for people using ask (ADR-0128). A change a user would notice updates it in the
same commit. `UserDocumentationTests` fails when a configuration key is undocumented, a link is broken, or a page other than its index
points into `development/`.

When a decision changes, supersede it. `status: superseded` with a `superseded-by:` link, never a
silent rewrite.

## Budgets

Four numbers, defined once in `AskCore.Budget` and printed by `ask --budgets`, so the measurement
script reads them from the binary rather than keeping a copy that can drift.

Report **median and spread, never the best run**. Percentiles, not averages. Interleave before-and-after
runs so background load cancels out of the ratio.

**Never trade correctness for speed.** `-Ounchecked` is banned: it strips the bounds and overflow checks
`StrictMemorySafety` depends on. Speed comes from doing less work.

The action-to-action budget is a tool call to its result on screen, for an in-process tool (ADR-0053):
`Scripts/measure-action.py` measures it, with the next request and a sandboxed `bash` command beside it.

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

Each concern has one owner, and `SourceStandards` enforces the first two:

- **JSON: AemiJSON** (ADR-0015), named qualified as `AemiJSON.JSONEncoder` and `AemiJSON.JSONDecoder`.
- **Command line: swift-argument-parser**, in the `ask` executable only.
- **Child processes: swiftlang/swift-subprocess** (ADR-0011), behind an injected interface.
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

- **Another writer may share the working tree.** Check `git status` for staged changes you did not make. Do
  not `git add -A` or reformat the tree with `quality.sh` under them; work in a clone and deliver a branch.
- **Splitting a file is not mechanical.** An unused `public import` is a compile error here, and `fileprivate`
  members that cross the new boundary must widen. Recipe: `.agents/skills/ask-structure/references/`.
- **A clone's `.build` cannot be reused.** Delete it; the paths are absolute.
- **SwiftPM 6.4 writes no index store** by default, so Periphery needs `--build-system native`.

## Working beside other agents

Several agents work in this repository at once. To keep `main` the meeting point:

- **One worktree per task**: `git worktree add ../ask-<task> -b <task> main`. Never edit the main checkout another
  agent may be using, and never `git add -A` there.
- **Merge each finished unit as soon as it is green**, not at the end: check `main`, rebase onto it, resolve
  conflicts in the worktree, run `Scripts/quality.sh --check`, then `git merge --ff-only` from the main checkout.
  A rebase that conflicts is resolved by reading both sides; the other agent's change is not discarded.
- **Leave nothing dangling**: after the merge, `git worktree remove` and `git branch -d`. Before ending a session,
  check `git branch -a` and `git worktree list`; a branch fully merged into `main` with no live worktree is deleted,
  locally and on `origin`. A branch checked out in another agent's worktree is theirs.
- **Take the next free number** for an ADR, roadmap entry or diary at the moment of writing, not at the start; it
  may have been taken meanwhile.

## Commit discipline

Before creating an ADR, diary or roadmap entry, reserve its number with `Scripts/next-number.sh adr|diary|roadmap --claim`.
Diary claims are per day (`--date YYYY-MM-DD` when needed). Claims cover this clone's branches and worktrees, not separate clones.
From a clean task worktree, `Scripts/land.sh` integrates, runs the full gate, fast-forwards local main and removes that task's worktree/branch; `--keep` retains it.
It never pushes. A failed gate/conflict keeps the task intact. Inspect the owner before removing a stale `.git/ask-land.lock`.

Atomic and buildable. The message states **why** — the diff already says what. Never mix a refactor
and a behaviour change. Slice by behaviour, not by file type.

A pre-existing issue found mid-task is reported as a follow-up, not silently repaired: a change that
fixes something the task did not name is harder to review, because the reviewer cannot tell the
requested change from the extra one.

## Current state

Targets: `AskCore` (budgets, documentation layout, source standards), `AskAI` (`Model` and `Transport` are provider-neutral;
providers are Claude (a subscription or a key), Codex (the ChatGPT subscription, over the Responses protocol), Antigravity
(Cloud Code) and any OpenAI-compatible or Responses server by configuration or preset), `AskAgentCore` (the loop, tools contract,
sessions, compaction, hooks), `AskTools` (`read`, `write`, `edit`, `bash`, jobs, sandbox narrowing), `AskMCP` (an MCP client),
`AskTUI` (the interactive screen) and the `ask` binary, which is the composition root and has **no tests** (roadmap 0028).
Skills (0061) and MCP (0067) are in progress. Not built: the codemode host (0012), the extension host (0033), subagents (0063), a
version and a release (0070); CI has never run (billing).

`development/roadmap/` says what is owed and in what order. What is *not known* is registered, with what would settle it, in
`development/research/` (`antigravity-2026-10.md`; the project-wide snapshot is `reassessment-2026-10-25.md`): read them before probing
something that is already written down as a question.

Read an entry's `status:` and `blocked-by:` before starting it.
