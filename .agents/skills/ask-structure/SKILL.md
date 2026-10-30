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

There is no baseline: every file meets every rule, and a file that cannot is split before it lands (roadmap 0025).

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

## Refactoring: ask the language first

Before extracting or hand-rolling, look at what Swift offers (white paper §8), then **compile the candidate**,
**pin behaviour first**, and **benchmark if it is on a request path**. What each idiom fixed here:

| Repeated shape | Idiom | Where |
|---|---|---|
| "decode input, else return the same error" in every tool | protocol with an associated type and a default method in an extension (template method) | `ArgumentTool` |
| `switch` over a `Result` to unwrap, in each body | typed throws, `throws(ToolFailure)` | `FileTools.text`, `.write` |
| a JSON string beside the struct that decodes it | result builder over typed property values | `ToolDefinition(name:description:) { ToolProperty… }` |
| `beginObject()`/`endObject()` pairs, `into: &writer` threading | scoped closure over an `inout` writer, like `withTaskGroup` | `JSONStreamWriter+Scopes` |
| two builders that differ in a literal | name the shape | `writer.typed(type, key, value)` |
| two enums that look alike | **leave it** if they differ in direction; accept with a reason | `ContentBlock`, `RequestBlock` |
| explicit `Codable` that dolly calls a clone | **leave it**: synthesized enum coding would change the on-disk format | `SessionLogRecord`, `WirePayload` |

Rejected, with reasons in ADR-0023: a macro to derive schemas (a swift-syntax target against a cold-start
budget) and `ExpressibleByStringLiteral` for `JSONObject` (a malformed literal would trap at first use).

How to probe: write the **old output as expected bytes first** (the four tool schemas are pinned in
`ToolDefinitionTests`), build the new form against it, then time old against new in one test, interleaved, with
the equality assertion inside the timing test. A public protocol's `associatedtype` makes the conforming type's
associated type public; budget for that.

## Static analyzers

`Scripts/analyzers.sh` (ADR-0022). Accept a finding with the tool's directive on the **line above the anchor**
(`// @dl:accept -- reason`, `// @dw:accept -- reason`, `// @al:accept -- reason`). dolly's near-clone matching
normalises identifiers and literals, so a test that restates a source shape with other names still matches;
change the shape, not the names. deadwood cannot see a global found by name (the Benchmark plugin's
`benchmarks`), which is why `Benchmarks/` is outside the corpus. `dead-store` and `unused-import` are off, with
the measurements in the diary. Planting a violation and requiring exit 1 is how a tool is proven; plant it so
it does not also trip another tool.

## Generic helpers: a decision, not a default

`Base64URL`, `FormEncoding` and `leftPadded` are in `AskAI/Support`. Aemi's `AemiKernel` has overlapping
`Base64`, `Hex`, `PercentCoding`, `ByteSearch`. The general rule ("generic tools belong in Aemi") was set
aside for these on 2026-10-19: they are small and specific to the sign-in and the stream, and adopting
Aemi's needs an equivalence test and, on the SSE path, a benchmark (ADR-0016). Revisit with a second
consumer, not before.

## What the global skills do not say

`references/skill-gaps.md`.
