# What exists for `ask serve` before anything is written (2026-11-14)

The owner, with the decision that serve speaks ACP: reuse the Aemi family and in-house code as far as possible, and probe for what
exists before implementing. Each row is a probe of the family's checkouts (`family/<repo>`) or of ask at `70f78038`.

| Need | Probe | What exists |
|---|---|---|
| JSON-RPC 2.0, both directions, any number of requests in flight | `grep -ril jsonrpc` over every family repository; `git ls-tree` of AemiJSON at ask's pin `806b481d` | **`AemiJSONRPC`**, a product of AemiJSON, in the pinned revision: `JSONRPCConnection` (requests matched by id with deadlines, the peer's requests answered by `onRequest` each in its own task, notifications in order, a cancellation notice), `JSONRPCMessage` parsing, `JSONRPC.request/notification/response` |
| One message per line, bounded | the same | `LineFraming` (8 MiB a line by default), and `ContentLengthFraming` for LSP |
| Standard input read off the cooperative pool | the same | `FileDescriptorChunks` over `AemiRuntime`'s `BlockingOffloadPool`; aemi is already in ask's graph |
| A stdio server in the family to copy the shape of | `grep 'import AemiJSONRPC'` | swift-search: `MCPStdio.serve` (server role) and `LanguageServerConnection` (client role) |
| Typed messages | ask's `Package.swift` | AemiJSON's `JSONDecoder`/`JSONEncoder`, `JSONValue`, `JSONStreamWriter` (ADR-0015) |
| A run's events as JSON | `Sources/AskAgentCore/Loop/JSONEventWriter.swift` | the `--json` objects, v1 (roadmap 0234 step 1) |
| The conversation, without a screen | `Sources/AskSession` | `AgentConversation` and its `ConversationUpdate` stream; `ConversationFixture` drives one in tests with no network |
| A tool call's title and full input | `Sources/AskTools/ToolSummary.swift` | `ToolSummary.header(for:)`, `fullInput(for:)` |
| MCP servers given at run time | `Sources/AskTools/MCPHub*.swift` | the hub takes stdio and HTTP servers from configuration; SSE is not built |
| A model of the session's states to check | `family/AemiFormal` | a TLA+ front end and model checker; not used by ask today. A candidate for the turn/cancel/permission state machine, not a need |

## Found on the way

- **ask's MCP client has a JSON-RPC of its own** (`AskMCP/MCPWire.swift`, `LineSplitter.swift`, 145 lines, and the id matching in
  `MCPConnection`), while `AemiJSONRPC` has existed in the pinned AemiJSON all along and carries an MCP cancellation preset. Not
  touched: it is the first finding of the audit the owner asked about (task t271).
- The fuzzer's `LineSplitter` finding of this morning (a limit applied differently to a whole line and a cut one) is in code that
  duplicates `LineFraming`. Whether `LineFraming` has the same flaw is not probed.

## Not found

- Swift types for ACP's schema: none in the family. They are written by hand for the subset used, or generated from ACP's
  published schema; which is the ADR's open question.
- ACP's Test Compatibility Kit was not read (what it is written in, what it needs to run).
