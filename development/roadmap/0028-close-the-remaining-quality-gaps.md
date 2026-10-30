---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0021
---

# 0028 — Close the quality gaps the audit found and the gate does not yet cover

Found by the 2026-10-19 audit (`development/diary/2026-10-19-02.md`), each with the probe that showed it.

1. **Unused imports are not gated.** Under `InternalImportsByDefault`, an unused `public import` fails the
   build but an unused `internal import` does not. deadwood's opt-in `unused-import` was measured (diary 07):
   270 findings, mostly "low" confidence, and one of its two "medium" ones was wrong (`Darwin`, used for
   `open` and `O_*`). Not gateable as it stands. Options: raise `--minimum-confidence` for that rule once the
   tool's heuristic sees module-qualified names such as `AemiJSON.JSONDecoder`, or a scan.
2. **`Sources/ask` has no tests.** `PrintRenderer` (output routing between stdout and stderr) and
   `ClaudeProvider` (auth per request) are behaviour, not binding. Move what can move into a library target
   and test it; leave only argument parsing in the executable.
   *(Partly done, 2026-10-26, diary 2026-10-26-01: `PrintRenderer` and the run's notices moved to
   AskAgentCore with 12 tests, and `ClaudeProvider` now binds through the tested `ModelStream.after` seam —
   the structure baseline shrank with `PrintRun.swift` leaving it. Then, diary 2026-10-26-02: `toolSummary`,
   `modelLabel`, the system instructions, the configuration directory and the instruction-file lines moved out of
   `Composition.swift` into libraries with 27 tests. Still untested in `Sources/ask`: `makeLoop` itself (it is binding:
   it names which library parts a run is made of), the command handlers and the flow of `runPrompt`. Read again after the
   move: the handlers (`/tree`, `/fork`, `/resume`, `/model`) hold only glue around library parts that have tests
   (`SessionOutline`, `SessionFile.fork`, the recorder) and are exercised end to end by `probe-tree`, `probe-fork` and
   `probe-interactive`, so item 2 is closed except for that glue.)
3. **Coverage is measurable and not reported.** 95.0% weighted line coverage over the library files today.
   By the project's own rule it is behaviour that counts, so this is a report in CI to show where a file has
   no test, never a threshold.
4. **`Benchmarks/Benchmarks` is outside the structure scan.** It is formatted and linted but a benchmark file
   can hold any number of types.
5. **Duplicate helper.** `leftPadded(to:)` exists in `AskAI/Support` and as a `fileprivate` helper in
   `AskAgentCore/Session/SessionDirectory.swift`. Aemi's `AemiKernel` has overlapping `Hex` and `Base64`;
   adopting them needs an equivalence test and, for anything on the SSE path, a benchmark (ADR-0016).
6. **Test-only code shipped in the binary. Closed** (ADR-0022): `SourceStandards` and `DocumentationLayout`
   moved to the test target, found by deadwood's `referenced-only-by-tests`. Binary -0.9%; idle memory about
   30-45 KiB lower, four interleaved rounds.
7. **The idle-memory budget is already exceeded on main.** 8208–8264 KiB against 8192 KiB, before this work
   (diary probe 18), so `ask --budgets` reports OVER BUDGET and the CI `budgets` job should be red. Roadmap
   0007 owns re-deriving the budgets; this entry only records that nobody is currently told. *Resolved 2026-10-20 by ADR-0038:
   the limit is 24 MiB; the overrun above is no longer a failure.*
8. **deadwood's `dead-store` rule was wrong on 13 of 13 findings here.** Two causes, fixed with tests on branch
   `fix/dead-store-false-positives` of g-cqd/deadwood, not yet released: a binding with no initialiser is not a
   store, and shorthand `if let x` reads the `x` it shadows. When a release carries it, bump the pin in
   `Scripts/analyzers.sh` (version and hash together) and re-measure before enabling the rule.
9. **CI has never run.** Every run in the repository's history failed, with no steps: GitHub will not start the
   jobs ("recent account payments have failed or your spending limit needs to be increased"). Needs the account
   owner. Until then the gates are `Scripts/quality.sh` and the hooks, and `.github/workflows/quality.yml`
   describes intent. When it does run, the `budgets` job will fail on idle memory (item 7).
10. **`Sources/ask` holds untested behaviour**: `AgentConversation.update(for:)` (loop event to screen update)
    and `toolSummary(name:input:)`. Either a small library target or an accepted gap; item 2 is the same issue.
11. **Show `AnthropicClient.endpointProblem` to the user** (ADR-0024). It needs `Composition.swift`, which was
    being rewritten on `robust-runs`; do it after that lands.
12. **`RetryPolicy.never` is public and unreferenced** on `robust-runs` (deadwood, `unused-public-api`), and that
    branch collides with the encoder refactor on `main` (`AnthropicRequestEncoder.swift`).
13. **The bash tool passes the whole environment to commands**, including `ANTHROPIC_API_KEY`. Decide with the
    sandbox work (0017-0022) whether to scrub it first. **Probed 2026-10-25: it does, and the value comes back to the provider in the tool result.**
    Moved to its own entry, roadmap 0072, with a red probe.
14. **`SessionFile.swift` is 246 of 250 lines**, with a 150-line struct body. The next change to it forces a
    split; do it deliberately, by behaviour (creating, opening, appending, forking), before then.

## Update (2026-10-25)

Item 2 now has numbers. `Sources/ask` is **3,301 lines in 65 files with no test target**, 11% of the 27,596 lines of source, against 2,086 tests everywhere else. Every provider
and every new command has landed in it: ModelDiscovery's catalog glue, the composition root, the provider adapters, the login commands. The Antigravity limits glue could be checked only by a
temporary line that printed the resolved window (diary 2026-10-25-10), and the composition of a provider is checked by live runs and by hand. What can move into a library target should
(the resolution of a model and its limits from a cache is the first candidate: it has no I/O of its own once the catalog and the settings are given), and what stays in the executable should be
argument parsing and wiring a person can see is wrong at a glance. Item 13 is roadmap 0072 and item 9 (CI) still needs the owner.

## Done when

Each item is either closed or has a recorded reason it stays open.

## The Benchmarks package is outside the gate (2026-10-30)

It went eleven days without compiling (0016's close-out). The gate should build it (`swift build --package-path Benchmarks`), at the cost
of about a minute warm; not added yet, because it lengthens every gate run and the owner sets that trade.

