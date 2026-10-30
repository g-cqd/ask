# Mutation testing and dependency tooling (2026-10-30)

The owner asked for mutation testing in CI and hooks, on edited files only, and for dependency graph checking and automated updates;
and, after Muter was tried first, to survey the means before choosing. This records the survey, the trials on ask, and a recommendation.

## Mutation testing

Surveyed (the owner's comparison, `~/Downloads/swift-mutation-testing-frameworks-comparison.md`, and the trials below): `swift-mutation-
testing` (ericodx, v1.6.4), `muter` (v17, master), `swift-mutants` (P4suta), `mull-xctest` (abandoned 2021, needs bitcode).

**Muter, tried first (a mistake of method: no survey).** Built from master in a private directory. On ask it introduced 36 mutants into
`ShellSegments.swift` and killed none: since its #302 (April 2026, a memory fix) `DiscoverMutationPoints` hands `ApplySchemata` an empty
parse cache, the file is parsed again, the mutation points are keyed by the first parse's nodes, and no switch is ever written. That is
also why the comparison measured "0 of 10 killed". Patched locally (keep the parse of files with mutants), it works: 16 of 36 killed in
4 min 37 s, but only after dropping `treatAllWarnings(as: .error)` from a copy of the manifest, because its inserted code warns. No
baseline, one worker, four operators. Not recommended; the bug is worth reporting upstream (owner's call).

**swift-mutation-testing, trial.** Built from v1.6.4 in a private directory; run on an untouched copy of ask (warnings as errors kept).
`plan` discovers 3,781 mutants in 817 files in 0.4 s; the plan, filtered to one file, runs with `run --plan`: one schematized build (81 s),
7 workers, three incompatible mutants built alone (raise `--build-timeout`, about 120 s each here). `ShellSegments.swift`: 22 of 28 killed
(78.6%) in about 5 minutes cold; the 6 survivors are real gaps in today's tests (escapes and the `<<` detection, lines 65 to 81). It
checks that a killed mutant's code ran (integrity warnings), caches verdicts per mutant, and gates on a committed baseline matched by
fingerprint (`--baseline`, `--max-new-survivors`, `--max-score-drop`), with SARIF and Markdown reports.

**Scoping to edited files.** No file-list flag: write a plan, keep the changed `Sources/**` files, run it with `--target` the matching test
target (`Sources/AskTUI/…` → `AskTUITests`). After one full run, the result cache alone keeps reruns to the changed mutants.

**Recommendation.**
- `Scripts/mutate-changed.sh [BASE]`: the changed `Sources` files against `BASE` (default `origin/main`), one plan per target, a run each,
  `--max-new-survivors 0` against `development/mutation-baseline.json`. Runnable by hand, by an agent before a commit, and as an opt-in
  pre-push task (`ASK_MUTATE=1`): about 4 to 6 minutes for one file cold, too slow to run on every push by default.
- CI: a job on pushes that touch `Sources/**`, running the same script against the push's base, with the cache directory cached; and a
  weekly full run that writes the baseline (estimated 30 to 60 minutes for 3,781 mutants on 7 workers; to measure).
- The tool is installed from a pinned release (version and SHA-256), as `Scripts/analyzers.sh` does for the analyzers.

## Dependency graph checking

What ask needs checked, and what already does it:
- One revision per package across the family: SwiftPM refuses a graph that disagrees; the benchmark and shipping manifests pinning the
  same stack: `RoadmapStatusTests` already checks.
- Each target imports only what it declares, and declares only what it imports: `tonyarnold/swift-dependency-audit` (imports against
  declared dependencies, per target). Fits; to trial.
- The target layering of ADR-0009 (0016's graph): `getyourguide/spmgraph` (graph visualisation and lint rules over SPM modules, 252 stars,
  maintained) or a small test over `swift package dump-package` JSON; the test is cheaper, the tool draws the graph too. To trial.
- Smaller or older candidates seen and set aside: `spm-audit`, `swift-package-audit`, `TargetDependencyChecker`, `cartograph`.

## Automated updates

- **Versioned dependencies** (swift-subprocess, swift-argument-parser, package-benchmark): Dependabot's `swift` ecosystem and Renovate's
  `swift` manager both read `from:`/`upToNextMinor` requirements and open pull requests; `MarcoEidinger/swift-package-dependencies-check`
  reports outdated ones without a bot. Dependabot is native to GitHub and needs one file.
- **The family's revision pins** (`revision: "<sha>"`): neither bot's Swift support reads them. Renovate's custom regex manager with the
  `git-refs` datasource can update a SHA to a branch's head, but not in the order the family needs (AemiRegex, then AemiMarkdown and
  AemiJSON, then TerminalKit, then ask), nor run each repository's gate in between. A script that does exactly what was done by hand today
  (heads, the cascade in order, each gate, one commit per repository) is the better fit: `Scripts/update-pins.py`, run on demand or weekly.

## CI, found on the way

ask's `quality` workflow had failed on every push since 2026-10-26 (`a270bf9`): it builds on macOS 26, the package's floor, where the
SDK lacks `LanguageModelError` and `SystemLanguageModel.variant`. Fixed in `046fcdc` (`canImport(FoundationModels, _version: 2)`). The
local gate cannot see this, so the workflow's result is checked after a push from now on.
