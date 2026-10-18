---
name: ask-structure
description: Where a new file, type, provider, tool or helper goes in ask, and how to split a file the structure gate rejects. Use when adding or moving Swift code, adding a model provider or a tool, when SourceStructureTests or ProviderNeutralityTests fails, when a file nears 250 lines, or when asked whether a design can take another provider or a harness feature. Not for the documentation directories (documentation-law) or for probing a claim (probe-before-adopting).
---

# Structure in ask

The file listing is the map of the project's types. ADR-0021 makes that a gate, so the tree stays an honest
map. The rules are source scans in the `AskCoreTests` target (`SourceStructure`), run by `swift test`, so the pre-push hook,
CI and `Scripts/quality.sh` all enforce them.

## The rules

1. **One top-level type per file, named for it.** Private types count. A nested type is free.
2. **Extensions** go beside their own type, or in `Base+Topic.swift` with one base per file. An extension whose
   every member is `fileprivate` or narrower is a file-local helper and may stay where it is used.
3. **No file over 250 lines**, tests included. Split by behaviour, not by line count.
4. **Test files:** one `@Suite` per file, named for it. A double used by one suite is nested in it; a double
   several suites use is a type with its own file.
5. **Provider names** (`Anthropic`, `Claude`, `OpenAI`, `Spettro`) appear only in `Sources/AskAI/Anthropic`,
   `Sources/AskAI/Claude` and `Sources/ask`.
6. A file that holds no type (free functions, constants) may have any name.

`SourceStructure.knownViolations` is a ratchet baseline: it shrinks, and never takes a new entry.

## Where things go

| Adding | Goes in |
|---|---|
| A type the loop or a tool speaks in (`ModelEvent`, `ToolDefinition`) | `AskAI/Model`, provider-free |
| HTTP, SSE, anything byte-level a provider reuses | `AskAI/Transport` |
| A small generic helper used inside `AskAI` | `AskAI/Support`. Not Aemi, by decision; see below |
| The loop, its settings, events, errors | `AskAgentCore/Loop` |
| The tool contract and registry | `AskAgentCore/Tools` |
| Sessions, their log, tree, files | `AskAgentCore/Session` |
| A tool's implementation | `AskTools`, one file per tool |
| Binding things together, argument parsing | `Sources/ask` only |

## Adding a provider

New directory `Sources/AskAI/<Provider>/` holding its client, request encoder, stream decoder (to
`ModelEvent`) and error mapping. Its auth, if distinct, is a second directory. Then one line in the
composition root in `Sources/ask` that builds a `ModelProvider`. Touch nothing in `Model`, `Transport`,
`AskAgentCore`, `AskTools` or `AskTUI`: if you must, the seam is bending, so stop and open an ADR
(roadmap 0026 lists what is already known not to fit). Neutral code is checked for the provider's name by
`ProviderNeutralityTests`; add the name to that list in the same change.

## Splitting a file

Recipe and traps in `references/split-recipe.md`. Short version: move one type per file with its doc comment
and attributes, nest a private helper into the one type that uses it, give each new file only the imports it
needs, and build once from the compiler's whole error list. Splitting is a refactor commit, never mixed with
behaviour.

## Generic helpers: a decision, not a default

`Base64URL`, `FormEncoding` and `leftPadded` are in `AskAI/Support`. Aemi's `AemiKernel` has overlapping
`Base64`, `Hex`, `PercentCoding`, `ByteSearch`. The general rule ("generic tools belong in Aemi") was set
aside for these on 2026-10-19: they are small and specific to the sign-in and the stream, and adopting
Aemi's needs an equivalence test and, on the SSE path, a benchmark (ADR-0016). Revisit with a second
consumer, not before.

## What the global skills do not say

`references/skill-gaps.md`.
