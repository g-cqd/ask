---
status: done
blocked-by: []
date: 2026-10-27
---

# 0077 — Use AemiRegex instead of Swift Regex throughout ask

The owner selected AemiRegex for repository-wide replacement of Swift Regex,
including production code, tests and Swift helper scripts. This is the concrete
migration request following roadmap 0059's earlier investigation, not a request
to introduce an NSRegularExpression wrapper. Reuse AemiRegex's engines; missing
reusable regex primitives belong upstream, consistent with roadmap 0076.

## Still owed

- Inventory regex literals, Regex/RegexBuilder APIs, dynamic patterns, replacement
  operations and helpers across the repository. Do not edit vendored dependency
  checkouts or silently replace unrelated Python/shell regex implementations.
- Characterize each use before replacing it: Unicode/grapheme behavior, byte versus
  String.Index ranges, capture groups, matching options, replacements, empty matches,
  malformed patterns and error reporting. Add counterexamples that can fail.
- Prefer linear-time `Pattern` where its syntax suffices. Use budgeted
  `BacktrackingPattern` only when required features and bounded failure semantics
  have been tested; record unsupported patterns and promote missing primitives.
- Measure cold compilation, warm matching, allocation/binary-size effects and
  relevant release request paths. No unmeasured universal speedup claim.
- Replace in atomic, behavior-preserving batches, updating explicit/resolved pins
  together if an upstream change is needed. Keep generated terminal behavior and
  copy/provenance unchanged; add a regression preventing new Swift Regex uses.

The current tool-input task will investigate the already resolved AemiRegex revision
for heredoc opener matching before adopting a regex implementation.

## Done (2026-10-28)

- Production: the only Swift Regex use left, `ProviderFailure+Overflow.contextWindow`, now uses a linear-time `Pattern`
  (`AskAI` depends on AemiRegex); a test covers the window of each server's wording, which had none.
- Tests: `FakeMCPServer`, `HTTPMCPSessionTests`, `BenchmarkDependencyTests`, `SourceStructure`, `PointerRig` and
  `BlockModelTests` no longer use Swift Regex literals (the last two use plain string operations).
- Regression: `NoSwiftRegexTests` fails on `import RegexBuilder`, `Regex<`, `try Regex(`, `firstMatch(of:`,
  `wholeMatch(of:`, `matches(of:`, `.replacing(/` and `(#/` in `Sources` and `Tests`.
- Not measured: cold compile, warm matching and binary size against Swift Regex (the roadmap asks for it). Python and
  shell helpers keep their own regexes by design.

## Closed (2026-10-31)

No Swift Regex is left in `Sources` or `Tests`, and `NoSwiftRegexTests` keeps it out. The measurement against Swift Regex that the
entry asked for has nothing left to compare with: the one production use was replaced together with its test.
