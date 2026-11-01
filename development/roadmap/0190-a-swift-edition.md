---
status: not-started
blocked-by: [0140]
date: 2026-11-01
---

# 0190 — A Swift edition: apple-docs connected, swift-search as a tool, sourcekit-lsp

Idea i2 (2026-11-01 21:13): a Swift-specific ask that connects the public apple-docs MCP instance from the start; with the swift-search
project, a dylib that gives ask a Swift project search tool directly; and an LSP connection.

Owner (2026-11-01): a separate binary, since not everyone wants it specific to Swift. But with the extension platform (0140) there is no
need for one: the same ask loads the Swift dylib, and the edition is that dylib plus its settings.

## Still owed

- 0140's design record and loader first.
- Until then, with nothing new: a preset (settings) that connects apple-docs and swift-search over MCP, as they work today.
- With swift-search's maintainers: the dylib's interface, built against 0140's.
- sourcekit-lsp: what the model gets from it (definitions, references, diagnostics after an edit) and how it is offered (a tool, or
  diagnostics attached to an edit's result).
