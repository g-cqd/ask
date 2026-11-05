# Repinning the family in seconds, 2026-11-05

Why moving one library forces a cascade of pin commits across the g-cqd and Aemi-Studio repositories, what is slow and what is not,
and leaner setups, with the one claim that needed a SwiftPM test tested. Answers note n3. Numbers come from
`development/research/probe-family-pins.py` (read-only; run it again for current ones) and from small SwiftPM probes on this machine.

## Where the time goes

| Step | Measured | Who does it today |
|---|---|---|
| Read all 26 manifests and check every transitive graph for conflicts | **0.2 s** (probe), 0.5 s with drift and order | by hand, repo by repo |
| `swift package resolve`, warm / `update` / cold clone (deadwood) | 1.1 s / 8.9 s / 39.6 s | per repo |
| A repo's `swift-ci run quality` | 5 to 50 s | per repo |
| Pushing 21 repos and waiting for CI | tens of minutes, mostly runners queueing (last repin) | per repo, in order |

So discovering the graph and checking consistency is sub-second work that people do by hand, and resolving is seconds. What costs
hours is the **cascade**: every one of the 58 edges between the repos is `revision: "<40 hex>"`, so a change at the bottom has to be
committed, pushed and (to be safe) tested in each repo above it, one dependency level at a time.

## The graph, as of today

- 26 manifests, 58 edges, **all** pinned by full revision (the `drift` command lists any that are not).
- Six levels deep (`order`): `aemi` -> AemiRegex, AemiMermaid, HTTP, ... -> AemiJSON, AemiMarkdown -> AemiProtobuf, TerminalKit ->
  analyzerkit, ask -> the six analyzers and swift-search.
- One bump forces: `aemi` 26 repos, AemiRegex 15, AemiJSON 12, AemiProtobuf 8, analyzerkit 7.
- The pins disagree with each other in time even though they agree in form. `aemi` is pinned by 21 manifests at **7 different
  revisions**, from the current head to 80 commits behind; AemiJSON at 3; AemiRegex at 2. Every transitive graph is nevertheless
  consistent (0 conflicts), which is what makes SwiftPM resolve.
- Most of these libraries have no tags (aemi, AemiRegex, AemiProtobuf, AemiMarkdown, AemiMermaid, TerminalKit: none; AemiJSON 5,
  analyzerkit 10), so a version requirement is not available for them today.
- Why a repo cannot simply pick its own spelling: SwiftPM compares requirements as written, so a package named by revision in one
  place and by branch in another fails even when both name the same commit (analyzerkit ADR-0025, case C2).
- The same cascade exists for CI: 23 repos carry swift-ci's 40-character SHA in `ci.yml` (2 distinct values at the time of
  measuring), and every swift-ci tool-lock change needs all of them edited.

## Options

**A. Script the cascade (no change to how repos depend on each other).** A `swift-ci` subcommand that reads the manifests, orders the
repos as `order` does, rewrites the pins to the new revisions, runs each repo's quality, commits and pushes level by level, and
repins `ci.yml` too. The check is 0.2 s; the time left is quality plus CI, so roughly one level at a time (6 levels) instead of
repo by repo (26), and nobody has to work out the graph. Keeps exact pins everywhere, so no repo's CI changes behaviour behind its
back. Cost: still one commit per repo per bump, still a CI wait per level.

**B. Pin by branch between repos; lock in the roots.** Libraries require each other as `branch: "main"` (one spelling everywhere,
which satisfies ADR-0025); only the roots (`ask`, the six analyzers, swift-search) commit a `Package.resolved`, which records exact
revisions. A bump becomes: push the library, then `swift package update` in each root. Tested:

> three local packages X <- A, B <- Root, with A and B requiring X at `branch: "main"`. After the first `resolve`, Root's
> `Package.resolved` named X at `9c87171`. I committed to X (`3fda7bd`) and ran `swift package update` in Root: **2.9 s**, X moved to
> `3fda7bd`, and A and B had **no new commits and no changes**.

The depth of the cascade falls from 6 levels and 26 commits to one commit per root, independent of each other. Costs to decide on:
(1) a push to `aemi` can now break a dependent's CI the next time it updates, not on the push; mitigate with a scheduled job that
runs the family at head and reports a break early, and keep `--force-resolved-versions` in CI (`ask` already does) so a build
never moves a pin silently; (2) the exact state is now recorded only in the roots' `Package.resolved`, so those files must be
committed and reviewed like pins; (3) a library's own CI would test against whatever its dependencies' heads are, unless it also
commits a `Package.resolved` for its own builds. Not tested here: this on the real graph, and indexstore-db, which is not a family
repo and keeps its revision spelling.

**C. Tag the libraries and require versions.** Same shape as B with `from:`/`upToNextMinor`, and a real compatibility contract. It
needs tags and a decision on what "compatible" means before 1.0 for six repos with none. Better long term; slower to reach.

**D. One lock file for the family, manifests generated from it.** A single `family.lock` (as swift-ci's `ToolLock.swift` already is
for the tools) listing every package's revision, with a generator that writes the pin lines into each manifest and `ci.yml`. A bump
is one edit and one command, but it still produces one commit per repo, so it removes the discovery work and not the cascade. Fits
with A.

**E. Test the integrated graph before pinning.** `ask` already has a mirrors file (`.swiftpm/configuration/mirrors.json`) that
points the family at local checkouts. A command that builds the roots against all local heads at once, before anything is pinned,
means the pin pass records a state already known to work, and a break shows up before 26 commits exist rather than half-way through.
Independent of A to D.

## Recommendation

Do **E** and **A** first: they change no repo's behaviour, and together turn "work out the graph, then repin 26 repos" into
"run one command, wait for CI". Then decide on **B** deliberately, because it is the only option that removes the cascade, and it
moves where reproducibility lives (into the roots' lock files) and when a break is noticed. **C** is the right end state for the
libraries that are ready to promise an API; **D** is a tidy-up that A makes easy.

None of this relaxes a gate: each option keeps every repo's quality and tests as the condition for a pin, and the performance,
safety, reliability and resilience budgets of `ask` and the analyzers are not touched by how the repos name each other.

## Not established

- B on the real graph (the test used three toy packages); in particular how the family's macros and the revision-pinned
  indexstore-db behave when the family-internal edges are branches.
- How long the full A flow takes end to end: the check and the resolve are measured, the CI queue is not under our control.
- That a scheduled "family at head" job is cheap enough on the runners available; it needs the Linux and macOS minutes.
- The probe reads only `https://github.com/g-cqd/...` and `Aemi-Studio/...` revision pins; other spellings are listed, not planned.
