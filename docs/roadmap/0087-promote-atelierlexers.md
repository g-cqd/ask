---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0087 — Promote AtelierLexers so ask can use it

The owner, 2026-10-28: AtelierLexers should be promoted. ask wants it for code fences in Markdown (0065 phase 5) and possibly for
the prompt's colouring (0085); it cannot depend on Atelier today.

## What it is, and what it drags (read 2026-10-28)

`Atelier/Packages/AtelierCore/Sources/AtelierLexers`: 585 lines of engine plus 1,888 lines of scanners (code, CSS, data, HTML,
per-language syntax tables), scanning a line at a time over borrowed UTF-8 from an entry state. It has tests, a corpus with a
checksum, allocation tests and throughput benchmarks (`Tests/AtelierLexersTests`).

Its dependencies inside Atelier's package: `AtelierHighlighting` (141 lines: highlight tiers), `AtelierSyntaxModel` (1,999 lines:
roles, tokens, merger, providers), and `TerminalKitText`. Both Atelier targets are broader than the lexers need, so the closure is
about 4,500 lines, of which the lexers use an unknown fraction (`import AtelierSyntaxModel` appears in 7 lexer files).
`AtelierSwiftSyntax` and `AtelierDocComment` depend on the lexers, so Atelier must keep consuming them after the move.

## The work

1. Decide the shape (owner, below), then measure what of `AtelierSyntaxModel` and `AtelierHighlighting` the lexers really use.
2. Move the lexers, the used part of the model and the tier protocol into one package with its own repository, history kept
   (`git filter-repo --subdirectory-filter`, then re-sign), tests and benchmarks included, same strictness flags as the Aemi packages.
3. Atelier depends on the new package and deletes its copies; its tests and benchmarks stay green and unchanged in result.
4. ask pins it at one revision and uses it for fenced code (0086).
5. Record a throughput and allocation comparison before and after, so the move is shown to cost nothing.

## Questions for the owner

- Name and home: an Aemi package (`AemiLexers`, in Aemi-Studio) or `g-cqd/AtelierLexers` kept under the Atelier name?
  0076 says reusable algorithms belong to Aemi subpackages, which points to the first.
- Should the highlight role model (`AtelierSyntaxModel`) move with it, or become a smaller `Role`/`Token` pair owned by the new
  package, with Atelier adapting?

## Done when

The package builds and passes its tests from its own repository; Atelier consumes it; ask renders a fenced block coloured by it.
