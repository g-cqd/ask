---
status: in-progress
blocked-by: []
date: 2026-11-04
---

# 0196 — AemiMermaid: a bounded Mermaid syntax reader, its limits, and the evidence for its budgets

The owner wants Mermaid drawn in the terminal (0066), in SwiftUI and in a Quick Look extension, with no third-party package (packages from `g-cqd`, `Aemi-Studio`, `apple` and `swiftlang` are fine, 2026-11-04), no recursion, linear time, safe and resilient (2026-11-04). The
prior art cannot be adopted: all six renderers run pass control bytes to their output, none bounds nesting, none fits a width (diary 2026-11-04-01, claims 1 to 3). So a new repository,
`AemiMermaid`, beside AemiJSON and AemiMarkdown, built the same way. This entry is its foundation: the syntax reader and phase 0. Design: `development/research/mermaid-markdown-quicklook-2026-11.md`.

## Phase 0, before any budget is adopted (the evidence rule)

- A quiet machine (the 2026-11-04 timings were taken at a load average of 25 to 100), release builds, median and spread.
- A corpus in the repository: the diary's 18 inputs, hostile ones that are permanent (3000 nested subgraphs, a 2 MB label, 20000 brackets, a star, a chain with back edges, complete bipartite graphs), and
  real diagrams from public READMEs (licences recorded). Which kinds a model writes when asked for a diagram is probed with a few prompts, as 0066 asked.
- Oracles run from scripts, never from a manifest: mermaid.js through `mmdc` if installed, `nessielabs/mermaid-swift`, `mmdflux`, `mermaid-ascii`, to compare what is accepted and how it looks.
- Budgets and limits **set from the step counts and p99 times**, then written into `MermaidLimits` and the tests.

## What is built

- Targets `AemiMermaidSyntax` (this entry) and a dev CLI `aemi-mermaid`; manifest like AemiMarkdown's (Swift 6, strict memory safety, warnings as errors, one Aemi pin, no dependency outside those four owners, tests included).
- Flowchart first, then sequence. UTF-8 bytes in, tapes out (Aemi's `TapeSlot`), offsets not copies, one pass over lines, nesting (subgraphs, fragments) on an explicit stack with a depth limit, no recursion anywhere.
- `MermaidLimits`: source bytes, nodes, edges, label bytes, nesting depth, messages, **sum of edge spans** (the virtual-node bound of 0197), and **fuel**, a count of steps. `MermaidDiagnostics` names the limit or the line and column.
  Never throws, never fails: unsupported syntax or a limit gives "source, with the reason", and nothing is ever half-drawn.
- **A sanitiser at the syntax**: control scalars, bidi overrides and unpaired surrogates never enter the tape. (The text backend filters again at the cell, 0198.)
- Linear in the bytes, checked by a growth test at 100, 200, 400, 800 and 1600 nodes (no wall clock: step counts), an allocation ceiling per diagram with `CAemiTestKitMalloc`, and a fuzz target.

## Red first

Each behaviour is a failing test first: the hostile corpus reaches the limits and reports them; an ESC in a label does not reach the tape; a malformed header gives a diagnostic with the line; the same input streamed in pieces or whole
gives the same tape; every input of the corpus finishes within its step ceiling.

## Done when

Flowchart and sequence parse the whole corpus within their ceilings, the gates of the family pass (format, lint, tests in release, deadwood, dolly, arcleak), the README states what is accepted, and the diary holds the phase 0 numbers.

## Performance, by measurement (research note, section 13)

Every technique is an experiment with a before and after and is reverted if no number moves: a single pass with SIMD classification of the special bytes of a line; node names interned into dense `UInt32` indices through a flat open-addressing table (no dictionary of strings); edges in compressed-sparse-row arrays; label text stored once in an arena and named by range; arenas reset per diagram and reused across diagrams, so a warm parse allocates nothing; a scalar reference parser kept in the tests as the oracle.

## Not in scope

Layout (0197), any backend, kinds beyond flowchart and sequence (state, class and ER follow in 0197 because they share the layout), Mermaid's `click` and theming directives (parsed and ignored, never run).

## Progress (2026-11-04)

The repository `AemiMermaid` exists with the syntax target: flowchart and sequence diagram parsers, `MermaidLimits`, bounded diagnostics, `LabelSanitizer` (layer one), the hostile-input tests (3000 nested subgraphs and fragments on a 512 KiB stack, the quadratic form of `&` groups, a 2 MB label, escape sequences) and a mutation fuzz over the corpus. Left from this entry: the oracle runner against the external renderers, a scalar reference parser and the fuel counter, state, class and ER, pie and Gantt, the SwiftLint and dolly gates of the repository, DocC.
