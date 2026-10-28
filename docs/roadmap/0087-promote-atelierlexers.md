---
status: not-started
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
