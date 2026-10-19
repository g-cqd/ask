---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0028
---

# 0033 — The extension host: tools and hooks from a child process

ADR-0028 decides that third-party code runs as extension processes speaking line-delimited JSON-RPC 2.0 over
stdio. This entry builds the host.

## The work

1. **The protocol, written down** before code: `initialize` (versions, declared tools and hooks), `tools/call`,
   `hooks/tool_call` (allow, block with a reason, rewrite), `hooks/tool_result`, `events/agent` notifications,
   `shutdown`. Field names follow MCP where the meaning is the same, so the transport can serve both.
2. **The host in its own target** (`AskExtensions`), over swift-subprocess (ADR-0011): one long-lived child per
   extension, started after the first frame (spawning measured 5 ms compiled and 25 to 53 ms for Python), its
   tools added to the registry once it answers, its hooks adapted to `AgentHook`.
3. **Configuration**: `~/.config/ask/extensions.json` lists executables; a project's own list loads only after the
   user trusts the project.
4. **A reference extension** with a test that runs it: one tool and one `tool_call` hook that blocks a command.
5. **Failure behaviour**: an extension that crashes, hangs or answers late never stops the run. Its tools report an
   error and its hooks fail open or closed as each hook declared, with the choice stated in the protocol.

## Done when

The reference extension runs end to end with a local model through `ask -p`, its block is enforced, and killing it
mid-run leaves the run alive and the user told. Sandboxing each extension is roadmap 0018's, applied here.
