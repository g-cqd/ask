---
status: done
blocked-by: []
date: 2026-10-28
---

# 0087 — Promote AtelierLexers as AemiLexers, inside a bigger AemiSyntaxTools

The owner, 2026-10-28: AtelierLexers should be promoted. ask wants it for code fences in Markdown (0065 phase 5) and possibly for
the prompt's colouring (0085); it cannot depend on Atelier today. Answers the same day: the lexers become **`AemiLexers`**, and
they may live in a bigger package, **`AemiSyntaxTools`**.

## What it is, and what it drags (read 2026-10-28)

`Atelier/Packages/AtelierCore/Sources/AtelierLexers`: 585 lines of engine plus 1,888 lines of scanners (code, CSS, data, HTML,
per-language syntax tables), scanning a line at a time over borrowed UTF-8 from an entry state. It has tests, a corpus with a
checksum, allocation tests and throughput benchmarks (`Tests/AtelierLexersTests`).

Its dependencies inside Atelier's package: `AtelierHighlighting` (141 lines: highlight tiers), `AtelierSyntaxModel` (1,999 lines:
roles, tokens, merger, providers) and `TerminalKitText`. `AtelierSwiftSyntax` and `AtelierDocComment` depend on the lexers, so
Atelier must keep consuming them after the move.

## Shape (owner's direction)

One package, `AemiSyntaxTools`, with products:

- `AemiLexers`: the engine and scanners (from AtelierLexers).
- `AemiSyntaxModel`: roles, tokens, merger, providers (from AtelierSyntaxModel).
- `AemiHighlighting`: the tiers (from AtelierHighlighting).

Not moved: `AtelierSwiftSyntax` and `AtelierDocComment` (they pull swift-syntax, which ask must not inherit); they stay in Atelier
and depend on the new package. The package depends on `TerminalKitText` only if the line sources need it; measure whether
that dependency is needed, because it ties the package to the kit.

## The work

1. Measure what the lexers use of the model and tiers (7 lexer files import the model), then fix the product list.
2. Create `g-cqd/AemiSyntaxTools` with history kept (`git filter-repo` over the three directories and their tests), re-signed as
   Gigi, same strictness flags and gates as the other Aemi packages, DocC.
3. Atelier depends on it and deletes its copies; its tests and benchmarks give the same results.
4. ask pins it at one revision and uses `AemiLexers` for fenced code (0086).
5. Record throughput and allocations before and after, so the move is shown to cost nothing.

## Done when

The package builds and passes its tests from its own repository; Atelier consumes it; ask renders a fenced block coloured by it.


## Folded into 0152 (2026-10-29)

The promotion is phase 1 of 0152, syntax highlighting wherever code is shown; this entry stays as its record.

## Owner (2026-10-31): a module inside aemi

The lexers become **`AemiLexers`, a module of aemi**, not a repository of their own. That needs the family's pin cascade (0166's
`update-pins.py --apply`) so ask, TerminalKit and Atelier reach the aemi revision that has it.

Measured the same day: the lexing core is the line lexer, its states, `SyntaxHighlighter` and the scanners (about 1,900 lines), plus
the model types they use (about 400 lines: `Language`, `HighlightRole`, `HighlightModifierSet`, `LineToken`, `UTF16Offsets`). It
needs only the standard library: no TerminalKitText, no Foundation. Atelier's tier engine (`LexicalHighlightEngine`, `LexicalTier`),
`ProgressiveHighlighting` (the one user of TerminalKitText) and the rest of `AtelierSyntaxModel` stay in Atelier, over `AemiLexers`.

## Progress (2026-10-31)

Steps 1, 2, 4 and 5 are done through 0152's phase 1 and 2: `AemiLexers` in aemi (`61b67bc`, `6e8279c`), its tests and the throughput
benchmark there, ask colouring fenced code with it at aemi `6e8279c`. **Step 3 is owed**: Atelier (HEAD `cccdb44`, pinning aemi
`bfc4f5a` and TerminalKit `8e39982`) still has its own copies; it must take aemi at `6e8279c` or later, delete them, map `Token` onto
its `HighlightToken`, and show its tests and benchmarks unchanged. The entry stays in progress until then.

## Step 3 done (2026-10-31)

Atelier consumes `AemiLexers` (Atelier `307bc4c` repins to aemi `00f8ea2`, TerminalKit `1d7076f`, AemiJSON `8ee749d`; `41e0ec0`
deletes the copies). aemi first made `LexStates.record(_:at:)` public (`00f8ea2`), which Atelier's progressive highlighting calls, and
took `UTF16Offsets`' tests with the type (`8d2feb8`).

- **The same results.** Before its scanner tests were deleted, Atelier's own 47 lexer tests ran against aemi's scanners and passed,
  but for the Swift, Java and C corpus checksums, which equal aemi's: there an exponent keeps its sign (`1.5e-3`, one number; aemi
  `6e8279c`). The engine's tests, its line scans through `LineTokens`, its allocation bound (4 a scan) and its benchmarks stay in
  Atelier. AtelierCore (1,568 tests), GitDiffViewer (1,161) and KittyCode (968) pass.
- **The cost.** Release, a 2 MB corpus per language, Apple M3, through `LexicalHighlightEngine.highlight(utf8:)`: 6 to 17% slower,
  median 10% (Swift 623 to 568 MB/s), because the engine now maps aemi's `Token`s to its `HighlightToken`s, one more array a scan
  (ADR 0022 keeps the generic entry point internal: public, it ran 3 times slower). The line-at-a-time path is unchanged (0.009 ms for
  the visible lines of a 1 MB side). Step 5's "cost nothing" holds for the scanners, not for that whole-text path; the remedy is an aemi
  entry point that builds a client's token without the generic cost, a performance item for Atelier's work queue.
- **The names.** `AtelierSyntaxModel` re-exports the five model types by name, so its clients see no scanner names (Atelier's grammar
  has a `LexState` of its own); `AtelierLexers` re-exports the whole module, as wide as before.
