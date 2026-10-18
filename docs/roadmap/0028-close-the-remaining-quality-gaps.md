---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0021
---

# 0028 — Close the quality gaps the audit found and the gate does not yet cover

Found by the 2026-10-19 audit (`docs/diary/2026-10-19-02.md`), each with the probe that showed it.

1. **Unused imports are not gated.** Under `InternalImportsByDefault`, an unused `public import` fails the
   build but an unused `internal import` does not, and the split left five. Periphery finds them but needs
   `--build-system native` for an index store and is noisy otherwise. Decide: a narrowed Periphery run that
   reports only unused imports, or a scan.
2. **`Sources/ask` has no tests.** `PrintRenderer` (output routing between stdout and stderr) and
   `ClaudeProvider` (auth per request) are behaviour, not binding. Move what can move into a library target
   and test it; leave only argument parsing in the executable.
3. **Coverage is measurable and not reported.** 95.0% weighted line coverage over the library files today.
   By the project's own rule it is behaviour that counts, so this is a report in CI to show where a file has
   no test, never a threshold.
4. **`Benchmarks/Benchmarks` is outside the structure scan.** It is formatted and linted but a benchmark file
   can hold any number of types.
5. **Duplicate helper.** `leftPadded(to:)` exists in `AskAI/Support` and as a `fileprivate` helper in
   `AskAgentCore/Session/SessionDirectory.swift`. Aemi's `AemiKernel` has overlapping `Hex` and `Base64`;
   adopting them needs an equivalence test and, for anything on the SSE path, a benchmark (ADR-0016).
6. **Test-only code ships in the binary.** `SourceStandards` and `DocumentationLayout` live in `AskCore`,
   which `ask` links. The new `SourceStructure` scanner was measured there (+33 KB of binary) and moved to
   the test target. The two older ones were not measured; moving them is the same change. Idle-memory effect
   is unknown and, per the diary (probes 16 and 17), not separable from page-layout noise by `measure-budgets`
   alone.
7. **The idle-memory budget is already exceeded on main.** 8208–8264 KiB against 8192 KiB, before this work
   (diary probe 18), so `ask --budgets` reports OVER BUDGET and the CI `budgets` job should be red. Roadmap
   0007 owns re-deriving the budgets; this entry only records that nobody is currently told.

## Done when

Each item is either closed or has a recorded reason it stays open.
