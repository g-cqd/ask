# What one request spends on tool definitions (roadmap 0137, 2026-10-31)

Measured with `Scripts/measure-request-size.py` on the release build of `583c465`: the first request of `ask -p hi`, captured by a fake
Anthropic server on 127.0.0.1, in compact UTF-8 bytes. Tokens were not counted: that needs a provider's tokenizer or its counting
endpoint, so a provider credential. A JSON schema tokenizes at roughly three bytes a token, so the estimates below divide by three.

## The numbers

| Setup | Request | Tools | ask's own | MCP |
|---|---|---|---|---|
| No MCP server | 6,183 | 5,032 | 5,032 | 0 |
| The owner's four servers (apple-docs, lldb, xcode, swift-search) | 24,619 | 23,468 | 5,895 | 17,573 |

- **ask's own six tools: 5.0 KB, about 1,700 tokens.** `read` is the largest (1.5 KB, a 576-byte description of its media options).
  The system line is 89 bytes and ask's instructions 969, the skill line included: skills cost one line, not 38 descriptions,
  because the `skill` tool searches them.
- **The owner's MCP servers: 17.6 KB, about 5,900 tokens, three-quarters of the tool block.** apple-docs (9 tools) and swift-search (9)
  are under the 16-tool limit per server (`MCPHost.defaultMaximumDirectTools`), so all 18 are sent in full. xcode (54) is over it and
  costs only `search_catalog` and `dispatch_call` (863 bytes). lldb did not start in either run (`lldb-mcp` timed out).
- **Repeats:** the per-call `sandbox` parameter is the same 377 bytes in `read`, `write`, `bash` and `narrow_sandbox`: 1,131 bytes
  beyond one copy, 22% of ask's own block. In MCP, swift-search's `workspace` description repeats in 7 tools (1,158 bytes beyond one).
- **Caching works:** the tool block and system line are byte-identical between the turns of a run, and the last tool carries a
  `cache_control` breakpoint. On Anthropic, the 23 KB are paid in full once per cache lifetime and at a tenth of the price after;
  what they also cost is context window, about 3% of 200k tokens. Providers without a cache, or a cache that lapsed during an idle
  pause, pay in full every turn.

## Candidates, from largest to smallest

1. **Fewer MCP tools sent directly** (up to ~15 KB with the owner's servers). Replace the per-server limit with a budget across all
   servers (by count or by bytes); the servers past it go behind `search_catalog`, as xcode does. Cost: the first use of a deferred
   tool takes one more round trip. `mcp.<server>.tools` already lets the person keep the tools they use most direct. **Owner's
   choice: the budget, and whether it is by count or bytes.**
2. **The per-call `sandbox` parameter** (about 1.1 KB). Either keep it on `bash` only, where a command can reach the network, and
   leave `read` and `write` to `narrow_sandbox`; or keep it everywhere with a shorter description. Its description also lists the
   network values the enum already gives (`network: none, localhost, provider or any`). **Owner's choice:** dropping it from `read`
   and `write` takes away a narrowing models may use.
3. **Small trims, not taken** (about 0.6 KB). Dropping `$schema` from MCP schemas (52 bytes in each of apple-docs's nine) would
   break a deliberate rule: a server's schema is carried byte for byte, never parsed and rewritten (`MCPToolParsing`, pinned by
   `MCPToolsTests`). It is also not strictly lossless, since `$schema` names the draft that decides how `$ref` and `$defs` read. The
   sandbox description's list of network values (about 180 bytes in all) repeats the enum; it goes with candidate 2, which rewrites
   that text anyway.
4. Repeated descriptions inside one server's tools (swift-search's `workspace`, `file`, `line`, `column`): the server's to fix,
   not ask's; JSON Schema `$defs` across tools is not something the tool APIs accept.

Shorter key names in tool arguments (the record's "reverse direction") were not pursued: argument names are what the model reads to
know what to write, and the arguments a model writes are a few dozen bytes a call.

## Not verified

- Token counts: estimated from bytes, not counted by a provider.
- The call success the record asks to measure before and after a cut: it needs a real model. The scripted suite's fake provider
  replays fixed calls, so it cannot show a model calling a slimmer tool wrongly.
- lldb's tools: the server did not start, so its share is missing.

## Owner's decision (2026-10-31)

Neither cut: the per-server limit of 16 stays, and so does the `sandbox` parameter in all four tools.

