---
status: accepted
date: 2026-11-06
supersedes: ADR-0092 (its reader of definition files; the rest stands)
---

# 0147 — Definition heads are read by AemiHMMML

## Context

ADR-0092 made `DefinitionFile` read any definition file without rejecting it. It did so with about 700 lines of parsers written
for ask: a YAML subset (`YAMLParser`, its blocks and values, `YAMLLine`, `YAMLHead`), `FlowParser`, `TOMLHead`, and fence code. The
owner asked (roadmap 0109) for the family's markup parsers to live in one package, and for ask's own to go. AemiHMMML now has
conformant YAML 1.2.2 and TOML 1.0/1.1 parsers with a recovering policy that never throws (its ADR-0001 and ADR-0014), and one
front matter locator (its ADR-0009 and ADR-0015).

## Decision

`DefinitionFile` keeps its interface: fields, comment hints, body, diagnostics, `isUnterminated`. What reads the file changes:

- The head is located by `AemiFrontMatter`: `---` YAML or `+++` TOML, blank lines and a BOM before it, CRLF, and an unclosed head
  read up to its first blank line, as before.
- It is parsed by AemiYAML or AemiTOML in recovering mode, with the comments' places recorded. A whole TOML file (Codex, Vibe) is
  read the same way. Limits for heads: depth 48, 1,000 aliases, 10,000 nodes expanded.
- `DefinitionReader` turns the values into `DefinitionValue`s with a stack of its own (`DefinitionBuilder`), not recursion. Scalars
  are the text they were written as: TOML numbers, booleans and dates as in the source, and a block scalar without its final line
  break. Tables made by headers or dotted keys flatten into `table.key`; inline tables stay maps.
- The behaviour ADR-0092 promised and the old parsers had is now the recovering parsers' general behaviour: a key written twice
  keeps the last value; a tab in indentation is indentation; `[WIP] fix the thing` is text; a line that is not `key: value` is
  skipped and noted. The last three were added to AemiHMMML for this.
- Hints come from the comments the parsers record. A list in a hint may carry a note after it (`[a, b] (effort: low)`): the
  longest part that strictly parses as a list is the value.
- Diagnostics are `line N: message`, and a repeated key says so as before (`the key `x` is written twice; the last value is used`).

## Evidence

- Every test of the reader, the tool and model tables, and the inspection report passes unchanged (`DefinitionFileYAMLTests`,
  `DefinitionFileTOMLTests`, `DefinitionFileFuzzTests`, `ModelPreferenceTests`, `ToolReferenceTests`, `DefinitionReportTests`), in
  release.
- The owner's harness corpus, read before and after with a dump of every field, hint, note and body length: 136 files (95 once
  symlinks are resolved; 14 TOML), identical. ADR-0092's 147 was an earlier count of the same directories.

## Consequences

ask no longer carries a YAML or TOML parser. A file that is valid YAML or TOML now reads exactly as the specifications say. Before,
a construct outside the old subset (anchors, tags, multi-line flow keys, TOML arrays of tables) read loosely; arrays of tables are now
lists of maps rather than flattened keys.
