---
status: accepted
date: 2026-10-23
---

# 0065 — A bare launch skips the argument parser

## Context

ADR-0015 gives the command line one owner, swift-argument-parser, and `SourceStandardsTests` bans
`CommandLine.arguments` everywhere in `Sources`. Roadmap 0054 asked why launches cost what they do, and the CPU time
matters because a launch that begins on an efficiency core pays about 1.6 times for every millisecond (diary 2026-10-22
(09)).

Profiling 60 launches of an executable that exits immediately attributed the samples to the loader's symbol resolution
(26%), system initializers (24%) and the rest of dyld. The cost that belongs to ask's own code, rather than to the
loader, starts with ArgumentParser: it reflects over `Ask`'s eighteen options and its seven subcommands on every
launch, including the one with no arguments at all.

## Decision

1. The launch logic moves, unchanged, into a plain `LaunchRequest` value whose defaults are a bare `ask`. `Ask` builds
   one from its parsed options; `Ask.main()` builds the default directly when there are no arguments. Both paths run
   the one implementation.
2. Any argument at all takes the ArgumentParser path exactly as before, including `--help`, errors, every option and
   every subcommand.
3. `CommandLine.arguments` is permitted in `Sources/ask/Ask.swift` only, and only to count it. The guard says so, and a
   second test fails if the exception is used for anything else or in another file.
4. A source-scanning test keeps the two paths identical: every `@Option` and `@Flag` in `Ask` must default to
   "not given", and `LaunchRequest` must declare the same property with the same default. The executable has no test
   target, so the scan is what stops an option added later from making a bare launch differ from a parsed empty one.

## Probes

Refuted before this one, each by a measured interleaved comparison of the executable that exits immediately
(`--noop`): relinking without chained fixups (7.93 vs 7.66 ms CPU, no gain), an async `main` (about 0.2 ms), the number
of linked libraries (a hello linking the same sixteen costs 0.5 ms more than Foundation alone), page faults (610 vs 595
minor faults against a Foundation hello) and a size-optimised build (18,633 vs 18,753 fixups, 5.22 vs 5.24 ms).

Measured for this change: 80 interleaved pairs per cadence of the baseline and candidate shipping builds from the same
tree. CPU saved per launch: median 0.92 ms paced (faster in 76% of pairs), 1.11 ms in a burst (66%). Cold wall time
about 0.8 ms in both, but only in 63% and 57% of pairs, so it is not claimed as established. The host was loaded
(7 to 21), so the paired differences carry the result, not the absolute times.

## Consequences

- A bare launch is roughly 7% cheaper in CPU. It does not remove the loader's symbol resolution, the larger cost, which
  only a smaller binary surface could reduce.
- Two entry paths exist. The parity test is the control; a change to launch behaviour belongs in `LaunchRequest.run()`,
  which both use, never in `Ask.main()`.
- The raw-argument ban now has one named exception.
