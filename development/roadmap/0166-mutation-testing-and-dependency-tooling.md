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
