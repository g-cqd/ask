---
status: accepted
date: 2026-10-19
---

# 0022 — Static analyzers are gates, pinned by version and hash

## Context

The gates before this measured style (swift-format), size (SwiftLint metrics) and, since ADR-0021, structure. None
read *meaning*: unused declarations, duplicated logic and retain cycles all passed. The owner publishes three
syntax-level analyzers for exactly these (deadwood, dolly, arcleak, on a shared `analyzerkit` model). They need
no build, share one CLI and JSON contract (1.x, frozen), and ran over this package in about 0.1 s.

## The probes

Full ledger in `development/diary/2026-10-19-07.md`. What decided the shape:

- **Each tool can fail.** Planted a dead function, a pair of 100-token clones and a stored closure capturing
  `self`: deadwood, dolly and arcleak each reported its own plant and exited 1, and exited 0 once it was removed.
- **On the real tree** they found what Periphery and the compiler had not: 7 clone groups that were real
  design signals (every tool repeated its argument decoding; every schema was hand-written JSON beside the
  struct that decoded it), 3 dead public helpers, a stale doc comment claiming a function was used by CI, and
  test-only scanners shipping in the binary.
- **Two opt-in deadwood rules were measured and left off.** `dead-store` was wrong on 13 of 13 findings, each at
  "high" confidence (deferred `let x: T` initialisation and shorthand `guard let x`); that is a deadwood bug,
  fixed on a branch of that repository. `unused-import` reported 270 findings, mostly "low", and was wrong on
  one of the two "medium" ones.
- **`Benchmarks/` cannot be analysed.** The benchmark plugin finds a global named `benchmarks` by name, which no
  syntax-level tool can see, so every benchmark reads as dead code and an accepted finding does not silence what
  hangs off it.

## Decision

1. **`Scripts/analyzers.sh` runs all three under `--strict`**, from `Scripts/quality.sh` (so CI and every local
   run), and as a pre-push task. They run before the tests: they read source, so they are the cheapest gate.
2. **Each tool is pinned to a release and to the SHA-256 of its macOS arm64 archive**, checked before anything
   is executed, and installed on first use into `~/Library/Caches/ask/analyzers`. Fingerprints move between
   versions, so an unpinned tool would turn a gate red for no change of ours. An upgrade changes the version and
   the hash together and reads the diff of findings.
3. **Corpus is `Sources` and `Tests`.** Reachability and clone detection are whole-program, so a smaller corpus
   makes live code look dead.
4. **Rules.** deadwood: the default rules, plus `unused-public-api` and `assign-only-property`, with `production`
   mode on and `referenced-only-by-tests` a *note*, which is visible and never fails. `dead-store` and
   `unused-import` stay off until the evidence changes.
5. **A finding ends in one of three ways: fix it, name the abstraction the duplicate was missing, or accept it at
   the source with a written reason** (`// @dl:accept -- why`, on the line above the anchor). No baselines: their
   fingerprints include line and column, so an edit above a baselined finding brings it back, and a baseline
   makes new debt look like old.
6. **Code only tests use does not ship.** `SourceStandards` and `DocumentationLayout` moved from `AskCore`,
   which `ask` links, to the test target.

## Amendment (2026-10-31)

The script and the pins moved to the family (analyzerkit roadmap 0031): `Scripts/analyzers.sh` now names a commit of
Aemi-Studio/aemi and runs its `Scripts/analyzers.sh` with its `Scripts/analyzers.lock`, which pins each tool's version
and the SHA-256 of its macOS arm64 and Linux x86_64 archives. The downloads go to `~/Library/Caches/g-cqd-analyzers`.
An upgrade moves that commit and reads the diff of findings. The decision is otherwise unchanged: deadwood 0.12.0,
dolly 0.12.0 and arcleak 0.13.0 report nothing new here.

## Consequences

- The gate needs the network on first run, and the owner's releases to stay available. A failed download or a
  hash mismatch is exit 2, never a silent skip.
- Three accepted findings carry reasons in the code: the session `Codable` shape (ADR-0013), the two block
  vocabularies, and the tool-use and tool-result wire shapes.
- Measured effect of moving test-only code out of the shipped target: binary 7,222,384 to 7,156,688 bytes
  (-0.9%); idle memory 8,320-8,336 KiB to 8,288-8,296 KiB over four interleaved rounds. The idle-memory budget
  (8,192 KiB) was already exceeded before this work and still is.
- The arcleak finding in the test double is accepted, not fixed: the task ends only when the test cancels it.
