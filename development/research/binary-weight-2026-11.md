# Binary weight across ask, the Aemi libraries and the dev tools, 2026-11-05

What gets linked into `ask` and the analyzer tools, what that costs a user and a CI run, and what could be taken out without giving up
performance, safety, reliability or resilience. Measured on this machine (Apple Swift 6.4.2, macOS 27 SDK, arm64; Linux in a
`swift:6.4` aarch64 container). Reproduce the macOS figures with `Scripts/measure-binary-weight.py`.

**Rule for every item below.** A smaller binary is not a goal on its own. Nothing here may remove a bounds or overflow check
(`-Ounchecked` stays banned, `Package.swift`), drop the symbols a crash report needs, or slow a path that has a budget (cold start 50 ms,
input 4 ms, action 8 ms, idle 15 MiB, active 20 MiB). Where a change touches one of those, the item says what to measure first.

## What was measured, and how far to trust it

| Claim | Evidence | Confidence |
|---|---|---|
| Sizes, sections, per-module code, dylib lists | one build of `ask` at `a1aaf5ba`, one of deadwood 0.16.0 | exact for those builds |
| RSS and launch cost of linked frameworks | minimal programs, 60 runs each, medians and minimums | measured, but in a toy program, not in `ask` |
| `-Osize` effect | two builds of the same commit; `measure-startup.py`, 16 cold starts each | size exact; startup measured; **steady-state speed not measured** |
| Linux Foundation cost | five tiny programs built with `-static-stdlib` | exact for those programs |
| Build-time share of swift-syntax | file timestamps of one 8.3-minute build | one build, on a machine with load average up to 32 |

The machine was shared and loaded (load average 8 to 32) during every timing, so timings use minimums and medians over many runs and
are compared only within one interleaved run.

## 1. `ask` today

`ask` is 22.4 MiB on disk and 12.4 MiB stripped with `strip -S -x`. It loads 45 dynamic libraries.

| Part | MiB | What it is |
|---|---:|---|
| `__TEXT` | 9.5 | code 8.3, strings, Swift metadata, unwind tables |
| `__DATA_CONST` and `__DATA` | 1.1 | |
| `__LINKEDIT` | 12.1 | **symbol and string tables: 333,303 symbols**, plus fixups and signature |

- **Stripping halves the file and changes nothing at run time.** 22.4 to 12.4 MiB (`strip -S -x`) or 11.1 MiB (full `strip`). Cold start
  26.1 ms against 26.0 ms, RSS 11,456 against 11,440 KiB (`--help`, 40 runs each). The symbols are not resident unless read. So the file
  size is a distribution and disk cost, not a speed cost. Cost of stripping: a crash backtrace has no names. Keep the dSYM (the build
  already writes one) with the binary that ships.
- **Code by module** (8.3 MiB of `__text`): standard-library specialisations 16.8 %, AskAgentCore 15.0 %, AskAI 12.2 %, AskTUI 7.9 %,
  ask 7.7 %, AskTools 4.6 %, then the libraries: AemiJSON and AemiJSONCore 6.8 % together, ArgumentParser and its tool-info 4.4 %,
  AemiRegex 2.6 %, Subprocess 2.4 %, AemiDiff 1.5 %, AemiMarkdown 1.6 %, the four Mermaid modules 2.1 %. In all, `Ask*` code is 49.8 %,
  `Aemi*` 18.0 % and `TerminalKit*` 5.0 %.
- **79 % of the code is hand-written bodies**; generated `Codable` code is not a factor. The largest functions are the schema validator's
  (10 to 12 KiB each).
- **Dead-stripping removes little.** For the larger modules, 66 to 100 % of the object code is still in the binary (AemiJSONCore 96 %, AskAI 87 %,
  AemiRegex 76 %). A library's footprint is close to its object size, so the lever is which modules are in the graph, not the linker.
- **swift-syntax is 0 % of the binary.** It is in the build graph for the macros only (section 4).
- Metadata that looks removable is small: reflection sections are about 290 KiB (1.3 %). Disabling them changes `Mirror` and
  `String(describing:)`; not worth the risk.

### Frameworks linked into `ask`

`import AppKit` (AskTUI, 2 files), `AVFoundation`, `PDFKit`, `ImageIO` (AskTools, for the read tool's media and PDFs) bring about
twenty Swift overlay libraries with them (`libswiftMetal`, `libswiftSpatial`, `libswiftCoreMIDI`, and so on).

| Minimal program | Dylibs | RSS (median) | Wall (min) |
|---|---:|---:|---:|
| Foundation only | 10 | 5,696 KiB | 9.0 ms |
| + AppKit | 19 | 7,440 KiB | 11.7 ms |
| + AVFoundation, PDFKit, ImageIO, UTType | 21 | 6,880 KiB | 11.5 ms |
| all of them | 23 | 8,256 KiB | 11.4 ms |

Linking them costs about **2.5 MiB of RSS and 2 ms before any code runs**, in a toy program. Against an idle budget of 15 MiB that is
a sixth. In `ask` itself this is not measured; the toy numbers say where to look, not what `ask` would save.

## 2. What `-Osize`, `-dead_strip_dylibs` and friends do

- **`-Xswiftc -Osize`**: `__text` 8.34 to 6.58 MiB (**-21 %**), stripped file 12.44 to 10.62 MiB (-14.6 %). With
  `measure-startup.py`, 16 cold starts each: p50 38.9 ms against 38.5 ms (no difference), minor page faults +7 % (1,630 to 1,743).
  `--help` RSS was 1.3 MiB *higher* (11.4 to 12.7 MiB). The startup order file (`Scripts/ask-startup.order`) was generated for `-O`; under
  `-Osize` 83 % of its 3,370 names still exist, against 95 % under `-O`. That may explain the extra faults and RSS; it is not proven.
  **Not established: steady-state speed** (rendering, JSON, the agent loop). Do not adopt before the order file is regenerated and the
  benchmarks (`Benchmarks/`, `measure-budgets.py`, `measure-action.py`) are compared on both builds.
- **`-Xlinker -dead_strip_dylibs`**: no change, 45 dylibs before and after. I did not confirm the flag reached the linker (the log was not
  verbose), so treat this as inconclusive, not as "does nothing".
- **Link-time stripping in the build** (`-Xlinker -S -Xlinker -x`) gives the stripped size above without a second step, but loses the
  symbols for the dSYM unless the dSYM is produced first. swift-ci already strips release archives; `ask` is built locally.

## 3. The dev tools (macOS and Linux)

Published sizes (stripped): deadwood 17.0 MB, arcleak 16.9, litmus 16.9, modeler 15.2, dolly 15.1, fcheck 15.0 on macOS.

- **swift-syntax is the weight**: in deadwood (attributed from the stripped binary's global symbols, so partial), SwiftSyntax 34 % of the code, SwiftParser 5 %, SwiftParserDiagnostics 3 %,
  SwiftSyntaxBuilder 1 %. Each tool imports only what it needs (SwiftSyntax, SwiftParser, and in four tools SwiftOperators or
  SwiftIfConfig); nothing to trim there. `SwiftParserDiagnostics` and `SwiftSyntaxBuilder` arrive through analyzerkit's use of
  `SwiftIfConfig`; about 350 KiB.
- **Six tools carry six copies of swift-syntax.** A single multi-call analyzer binary (one executable, tool chosen by name or
  subcommand) would store it once: roughly 5 x 13 MB saved on disk and in every artifact. It changes release, baseline and versioning
  of six repos, so it is a decision, not a fix.
- **Linux archives are 30 MB compressed, 92 MB unpacked, per tool** (macOS: 5 MB). The executable is 16.8 MB; the rest is the Swift
  runtime beside it, and `lib_FoundationICU.so` alone is 38.6 MB. The artifactbundle (what SwiftPM consumers download) is 35 MB.
- **Why: one reference to full `Foundation` links all of it.** Linux, `-static-stdlib`, stripped:

  | Program | Size |
  |---|---:|
  | `print("hi")` | 5.5 MB |
  | `import Foundation`, unused | 5.5 MB (nothing is linked) |
  | `import FoundationEssentials`, `FileManager` and `JSONDecoder` | 12.1 MB |
  | `import Foundation`, one `Thread` | **54.1 MB** |
  | deadwood, static | 78.8 MB (rodata 38.3 MB of ICU data, text 22.6 MB) |

  So the cost is not importing Foundation, it is touching a symbol that only full Foundation has.
- **Two such references found in deadwood's graph, both removable:**
  1. `AemiRuntime` (`BlockingOffloadPool.swift`) uses `Foundation.Thread` and `QualityOfService`, and `public import Foundation` puts
     both in its public initialiser. **Every consumer of AemiRuntime inherits full Foundation on Linux**, including everything that
     depends on AemiRegex (AemiRegex depends on AemiRuntime).
  2. analyzerkit `ProjectModel/XcodeSchemes.swift` uses `JSONSerialization`, `replacingOccurrences(of:with:)` and
     `range(of:range:)`. All have Foundation-free equivalents (a `Decodable`, `firstRange(of:)`, `split`/`joined`).
- **Not enough on their own.** I patched both in a scratch copy (a `pthread` in place of `Thread`; `JSONDecoder` and local helpers) and
  rebuilt: deadwood stayed 78.8 MB and still contains the ICU data. A scan of every object file found no remaining reference to
  `$s10Foundation`, so a third root exists that I did not locate. **Next step:** link `deadwood` alone with lld's `--why-extract`
  (it names the object that forced each archive member in); I could not get that flag through SwiftPM's build in the time I had.
- **What this buys in CI is small.** Installing a Linux tool takes about 1.5 s (measured in deadwood's CI log). A Linux job spends 28 to
  39 s initialising its `swift:6.4.1-noble` container, and swift-syntax is built or cached. The weight matters for consumers of the
  artifactbundle and for disk, not for the pipeline's wall time.

## 4. Build time: swift-syntax is built from source in `ask`

In a clean `ask` release build (522 s wall), the swift-syntax modules were being compiled from **minute 0 to minute 6.3 of the 8.3 minutes**
of compiling (SwiftSyntax alone 4 m 46 s, in parallel with other modules), and none of it ends up in the binary. SwiftPM 6.4 has a prebuilt swift-syntax for macro
builds; it downloaded the 604.0.0 prebuilt (21 MB) and still compiled from source.

I tried to reproduce this in small packages and **could not**: seven shapes all used the prebuilt (build 4 to 14 s). They covered a
macro with one and with ten swift-syntax products; a regular target importing SwiftSyntax beside the macro; that target in a second
package; the macro in a dependency, with and without the root declaring swift-syntax; and a macOS 26 deployment target. So the trigger
in `ask`'s graph is unidentified. **Next step:** bisect in a scratch copy of `ask`, removing aemi, AemiJSON and AemiProtobuf in turn from
the graph until the prebuilt is used.

## 5. The Aemi libraries: where they overshare

Consumers import granular products (checked in 16 repos), never the umbrellas `Aemi` or `AemiFoundation`, and no production target links
a test kit (checked in 7 repos). The design works. The oversharing is in specific edges:

| Edge | Cost to a consumer | Fix |
|---|---|---|
| `AemiJSONCore` depends on `AemiRegex` (JSONPath `match()` and `search()` only) | a JSON-only consumer links a regex engine: 287 KiB of objects, 219 KiB kept in `ask`. Also pulled in by `AemiProtobufJSON`. | move JSONPath to its own target and product, or inject the matcher; update the stale `AemiJSONCore` comment ("no transitive package deps") |
| `AemiRuntime` `public import Foundation`, `Thread`, `QualityOfService` in its public API | full Foundation on Linux for every consumer (section 3) | `pthread`/`Thread`-free worker start and an Aemi QoS type, behind the same behaviour; test thread naming, priority, shutdown |
| `AemiJSON`, `InternedStrings`, `Loggable`, `Aemi`, `AemiProtobuf` products carry ten swift-syntax products | none in the binary (0 % linked); build and resolution time only | none needed if section 4 is solved; otherwise a macro-free product for each |
| `@_exported import` in 16 places in aemi, 7 in AemiJSON, 2 in AemiProtobuf, 1 in AemiSDR | namespace, not size: `Loggable` re-exports Foundation and OSLog, `AemiJSON` re-exports OrderedCollections, `AemiSDR` re-exports SwiftUI | re-export only types that appear in the public API; the rest is source-compatible to remove behind a minor version |
| `@inlinable` 201 and `@usableFromInline` 37 in aemi; 111 and 54 in AemiJSON; 26 in AemiProtobuf | code copied into each client and tied to the library version | no change proposed: these are performance decisions. Require a benchmark for each new `@inlinable`; audit the existing ones by bytes inlined per use |
| `AemiKernel` (83 KiB) is in every closure | fixed cost of the foundation tier | none; it is shared |

## 6. Actions, ranked

Each says what it saves, what it risks, and how to know it is safe.

| # | Where | Action | Saves | Risk and check |
|---|---|---|---|---|
| 1 | aemi `AemiRuntime` | remove `Thread` and `QualityOfService` from the public surface | Linux: lets every consumer drop full Foundation (with 2 and 3) | thread start, naming, priority, shutdown are behaviour: keep the existing tests, add a stress test for pool shutdown |
| 2 | analyzerkit `ProjectModel` | replace `JSONSerialization`, `replacingOccurrences`, `range(of:)` | same | `XcodeSchemes` tests cover the scheme and test-plan readers; add a case for entities and a malformed plan |
| 3 | locate the third Foundation root in deadwood | `--why-extract` on the final link | decides whether 1 and 2 are enough | none; analysis only |
| 4 | ask, build | find why swift-syntax is built from source | up to about 5 minutes of a clean build and of a CI cache miss (the critical path, not a measured saving) | none to the product; check the macro expansions are unchanged |
| 5 | AemiJSON | split JSONPath from `AemiJSONCore` | about 0.3 MiB for JSON-only consumers, one fewer dependency for AemiProtobufJSON | source-compatible if `AemiJSON` re-exports the new product |
| 6 | ask | decide on the frameworks: lazy-load AppKit (clipboard) and the media frameworks (read tool) | up to about 2.5 MiB RSS and 2 ms (toy figure) | **measure in `ask` first** with `measure-budgets.py`; a lazy load adds a failure path (`dlopen` can fail): it needs a tested fallback |
| 7 | ask, release | ship the stripped binary with its dSYM | 10 MiB per release artifact | a crash needs the dSYM from the same build; archive them together |
| 8 | ask | `-Osize`, only as an experiment | -21 % code | regenerate the order file, then run the benchmarks on both builds; no adoption on size alone |
| 9 | swift-ci | record the stripped size of every release archive and fail a release that grows by a set percentage without a note | catches a regression like action 1 returning | threshold chosen by the owner |
| 10 | analyzers | decide on one multi-call binary | about 65 MB of the six tools' swift-syntax copies | release, baseline and version coupling across six repos |

## 7. Not established

- Why the prebuilt swift-syntax is not used in `ask` (section 4).
- The third full-Foundation reference in deadwood (section 3).
- Whether `-dead_strip_dylibs` reached the linker (section 2).
- Steady-state speed under `-Osize`, and whether regenerating the order file removes the extra page faults.
- The real RSS saving in `ask` of lazy-loading frameworks (the 2.5 MiB is from a toy program).
- Linux x86_64: all Linux numbers are aarch64. The published x86_64 archive has the same shape (30.6 MB) but I did not build there.
- Binary weight of anything but `ask` and deadwood. The dependency structure was read for 16 repos; sizes were measured for two.
