---
status: accepted
date: 2026-10-19
---

# 0023 — A tool declares its arguments once

## Context

dolly's exact-clone findings across `ReadTool`, `WriteTool`, `EditTool` and `BashTool` were the same preamble four
times (decode the input, answer a malformed one with the same error), and the near-clone beneath it was each
tool's `definition`: a hand-written JSON schema behind `try!`, beside the `Arguments` struct that decoded the
same fields. Every future tool would copy both, and a schema and its struct could drift apart unseen.

The rule adopted the same day (white paper section 8) is to ask what Swift already offers before hand-rolling.

## The probes

- **Protocol with an associated type, and a default `run` in an extension** (a template method) removes the
  preamble. Compiled and run against the existing tool, loop and registry tests, which passed unchanged.
- **Typed throws instead of `Result` and optional-failure shapes.** `FileTools.text` and `.write` now
  `throws(ToolFailure)`, so bodies use `try`. The project's Swift guidance already says typed throws over `Result`.
- **A result builder for the schema.** `ToolProperty` values declared in a `@ToolSchemaBuilder` closure. Probed
  by writing the byte sequences the four tools used to hand-write as expected strings first, then checking the
  builder reproduced them exactly (including escaping and an omitted `required`), then pinning the real tools'
  schemas the same way. A provider caches the tool list as part of the prompt, so a moved byte would be a cache
  miss for every user.
- **Scoped writer closures** (`writer.object { }`, `.array { }`, `.typed(…)`) over AemiJSON's `~Copyable`
  `JSONStreamWriter` compile and read as the structure of the JSON. The encoder's output was asserted identical on
  a 31,843-byte request, and was not slower: 39.5 µs per encode against 40.1-40.2 µs, over 15 rounds twice.
- **Rejected:** a macro that derives the schema from the `Arguments` struct. It removes the last duplication
  between struct and schema, but adds a swift-syntax macro target to a project with a cold-start budget. Recorded
  for when a second provider or the codemode host makes schemas more numerous.
- **Rejected:** `ExpressibleByStringLiteral` for `JSONObject`, to shorten `try!` test fixtures. It would turn a
  malformed literal into a trap at first use.

## Decision

1. A tool conforms to `ArgumentTool`, states `Arguments`, and implements `run(_ arguments:in:) async throws(ToolFailure)`.
   The `Tool` contract (`run(_ input: JSONObject, …)`) is unchanged for everything else; `ArgumentTool` supplies it.
2. `ToolFailure` is part of the tool contract and lives in `AskAgentCore`.
3. A tool's `definition` is built with `ToolDefinition(name:description:) { ToolProperty… }`. Hand-written schema
   JSON is no longer how a tool says what it takes.
4. `JSONStreamWriter` scopes (`object`, `array`, `field`, `typed`) live in `AskAI/Support`, internal.

## Consequences

- A protocol's associated type is part of its surface: each tool's `Arguments` had to become `public`. Its members
  stay internal. Putting the protocol at `package` access would hide the tools' `Tool` conformance from outside
  the package, which is worse.
- The removed `Tool.arguments(_:from:)` and `ToolArguments` were public API with no caller outside the tools.
- Schema and `Arguments` are still two declarations that must agree. The builder makes the schema checkable and
  short; it does not tie it to the struct. Roadmap 0027 (tool metadata such as read-only) now has one place to
  put it.
