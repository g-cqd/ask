---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0166 — Mutation testing on changed files, dependency checks and pin updates

Owner (2026-10-30): plug mutation testing into CI and hooks, on edited files only; dependency graph checking and automated updates. The
survey and the trials: `development/research/tooling-mutation-and-dependencies-2026-10-30.md`.

Proposed, for the owner to confirm:
1. `swift-mutation-testing` (pinned release) through `Scripts/mutate-changed.sh`: changed `Sources` files, a plan per target, a committed
   baseline, `--max-new-survivors 0`; opt-in pre-push task (`ASK_MUTATE=1`), a CI job on `Sources/**` pushes, a weekly full run.
2. Trials of `swift-dependency-audit` (declared against imported dependencies per target) and `spmgraph` (layering, the graph drawn).
3. Dependabot for the versioned dependencies; `Scripts/update-pins.py` for the family's revision pins, in order, each repository's gate
   between.
4. Tests for the six mutants that survive in `ShellSegments.swift` (escapes, `<<` detection, lines 65 to 81).

## Owner (2026-10-31): all four confirmed

Build proposals 1 to 4. Muter's empty-`ApplySchemata` bug is reported upstream only if the repository is still active. The open
Dependabot PRs (AemiRegex #1, aemi #4) are reviewed and merged when each repository's gate passes.

## Done (2026-10-31): part 4, and a bug the tests found

`ShellSegmentsEdgeTests` pins the exact segments at each edge the six survivors sat on: a backslash ending the line, backslash-newline,
an escaped separator, `<<` at the end of the line, a lone `<`, and `<<<`.

The `<<<` test failed. A here-string was read as `<` and then `<<`, which opened a heredoc whose "body" swallowed the next lines. So
`cat <<< x` followed by `rm -rf build` on the next line named only `cat`, and a session approval of `cat` would have covered the `rm`.
Fixed: `<<<` is read as a whole before `<<` is looked for (`opensHereString`). The heredoc check lost its `<<<` clause, which was now
dead code. Regression test in `CommandWordsQuotingTests`. The mutation run to confirm the score comes with part 1.

## Done (2026-10-31): part 1, mutation testing on changed files

- **`Scripts/mutate-changed.sh [BASE | --all | install]`** installs swift-mutation-testing v1.6.4 from its release, checking the
  pinned SHA-256. It plans the package, keeps the `Sources` files changed against `BASE` (committed, staged or new), and runs one
  plan per target with that target's tests. `--baseline development/mutation-baseline.json --max-new-survivors 0` is the gate.
  `Sources/ask` has no test target, so its files are skipped and named. `--all` rewrites the baseline from every target's.
- **The baseline starts empty.** No full run has been done yet, so any survivor in a changed file counts. The weekly CI run
  (`.github/workflows/mutation.yml`) uploads a full baseline as an artifact, to commit by hand.
- **Measured.** `ShellSegments.swift` after part 4: 28 of 28 killed. The first run took 20 minutes cold, with aemi's build and tests
  running at the same time; the rerun took 0.5 s from the cache (`.swift-mutation-testing-cache/`, ignored by git).
- **Tool caveats.**
  - Report and baseline paths must be relative to the project. An absolute `/tmp` path ended a 20-minute run with exit 1 and no
    report, so the script writes to `.build/mutation/`.
  - Every kill is reported as "killed without activation": the tool's activation probe does not reach SwiftPM's test processes.
    The kills are real (negating the scan loop's condition breaks every test), so `--max-integrity-warnings` is not used.
- **Hooks.** An opt-in pre-push task in `.project-hooks.yml` runs only with `ASK_MUTATE=1`. AGENTS.md lists the script.

## Done (2026-10-31): part 3's Dependabot PRs, and aemi's failing main

- **aemi's `main` failed CI on every run, independently of the PR**, in two places:
  - Swift 6.3.3 rejected `Merge.parallel`. Its `concurrentPerform` takes a `@Sendable` closure, so `body` is now passed through a
    `nonisolated(unsafe)` constant, called with `unsafe` under strict memory safety.
  - The sanitizer job's `bench-c-kernels.sh` reads `3e64286^`, which a shallow checkout lacks, so the job now uses `fetch-depth: 0`.
  - Fixed in aemi `d557375`. The local toolchain's 6.3.3 cannot compile the manifest against this Xcode's SDK, so the 6.3.3 build
    is verified only by CI.
- **aemi #4 and AemiRegex #1 (`actions/setup-go` 5 → 7) are merged** with signed merge commits, pushed over SSH: aemi `182ab81`,
  AemiRegex `71f44b4`. The bump's own job passed on both PRs. AemiRegex #1's failing static-analysis check came from the `main` it
  was opened against, which was failing then and passes now.
- **`gh` is signed in to the work account (`coquard_ocu`)**, which cannot write to these repositories, and must not. So the merges
  went through git with the personal key; git in `g-cqd/` folders uses that key (`~/.gitconfig-g-cqd`).
- **Muter: not reported again.** Its repository is active (last commit 2026-10-23), and the bug is already open as muter #321
  (2026-10-11), with the same root cause and fix.
