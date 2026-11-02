---
status: proposed
date: 2026-11-02
---

# 0142 — Compiled extensions are a C table in a signed dylib, loaded on first use

Design record for roadmap 0140 and the owner's idea i3 (2026-11-01): a developer extends ask with dylibs for fast features, first
tools, LSP servers and hooks; beside MCP, not instead of it. Proposed, not accepted: the questions at the end are the owner's to decide,
and nothing is built.

## Context

- **Routes today.** Tools from outside come through MCP (ADR-0123, roadmap 0067). Hooks are to come through the extension host, a child
  process speaking JSON-RPC over stdio (ADR-0028, roadmap 0033, protocol drafted, host not built). ask's own tools are compiled in.
- **What a child process costs** (roadmap 0114, measured on this machine). One stdio JSON-RPC call with a small payload takes 20 µs to a C
  server and 26 to 36 µs to Python, Node or Bun. With 16 calls in flight it takes 5 µs. A 256 KB payload takes 137 to 288 µs. Spawning
  costs 5 ms for a compiled server and 25 to 53 ms for Python, paid once, after the first frame. The input budget is 4 ms and the action
  budget 8 ms. So per call, a process costs under 1% of a budget, and **call latency alone does not justify a dylib.**
- **What would justify one.** These are what a process cannot do cheaply:
  - work on large state on every call: the transcript, the context, a whole index;
  - share memory with ask, so a symbol index (0190's swift-search) answers without copying;
  - many calls a turn, such as a hook on every streamed event;
  - no second process to start, keep and watch.
- **The binary.** `Scripts/sign.sh` signs ask with the hardened runtime and no exceptions. So dyld loads only libraries signed by Apple or
  ask's team, and nothing else can run as ask and read its Keychain items without a prompt. An ad hoc build (no identity) has no library
  validation.
- **Swift has no stable binary interface** between a plugin's compiler and ask's for Swift types. `dlclose` is not dependable for Swift
  images.
- **Trust today** is per file as it is now (`trusted.json`, a hash): a project's skills, configuration and MCP servers load only once
  trusted.

## Decision (proposed)

1. **One C entry point, one versioned table.** A dylib exports `ask_extension_v1`, a `@_cdecl` or C function. It takes the host's table
   (the version, the table's size, a log function and a free function) and returns the extension's: version, size, name, and
   `call(kind, name, bytes, length, reply)`. Bytes in and out are the JSON of the routes that exist: MCP's `tools/call` for a tool, and
   0033's `hooks/tool_call` and `hooks/tool_result` for a hook. So the same extension can ship as a dylib or as a process, and ask
   adapts a dylib with the code it has. A newer table only adds fields at the end; ask reads `size` and refuses a version it does not
   know, by name, in the transcript.
2. **A manifest beside the dylib, so nothing loads at launch.** `name.askext/` holds `extension.json` (tools with their schemas, hooks
   with their points and whether each fails open or closed, the table version) and the dylib. Tools are offered from the manifest. The
   dylib is `dlopen`ed at the first call of one of its tools or hooks, so cold start pays nothing and an unused extension costs no
   memory. Once loaded it stays loaded, and `/reload` re-execs ask, as now.
3. **Library validation stays.** ask keeps the hardened runtime without `com.apple.security.cs.disable-library-validation`. A signed
   ask therefore loads only dylibs signed by its own team: the owner's own extensions, or a third party's re-signed by the person who
   built ask. An ad hoc ask loads any dylib, and then trust is the only gate. Turning validation off for third-party dylibs would undo
   the Keychain protection for every user, so this record refuses it.
4. **Trust per dylib, by its code-directory hash.**
   - A user extension (`~/.config/ask/extensions/`) is asked about once, when first used.
   - A project's extension waits until the project is trusted, and is then asked about on its own.
   - A changed dylib (a new hash) is asked about again.
   - The prompt says plainly that the code runs inside ask with ask's rights.
5. **No sandbox inside the process.** Seatbelt applies to a whole process. So a dylib runs with ask's full rights, and with its
   network, files and Keychain. Therefore:
   - its tools are refused in a narrowed session, as MCP tools are (`MCPToolAdapter.narrowedRefusal`);
   - its hooks still run there, since a hook can only block or rewrite;
   - a dylib that crashes takes ask down with it. This is why **the process route stays the default**, and the dylib route is for
     extensions whose authors measured the need.
6. **Hooks have two routes and one meaning.** 0033's hook points are defined once (`AgentHook`). A process extension and a dylib
   reach them through two adapters, with the same JSON and the same fail-open or fail-closed rule. A dylib whose call does not return
   within the hook's limit cannot be killed. It is then stopped from being called again, and the transcript says so.
7. **LSP servers stay processes.** A language server is a process by its protocol, and sourcekit-lsp ships as one. A dylib extension can
   offer language tools (definition, references) over its own index; it is not a way to load an LSP server.
8. **Budgets.** A loaded dylib's memory counts in ask's RSS budgets (15 MiB idle, 20 MiB active), so a large index belongs in a process.
   The load happens on first use, inside that call's action budget, and is measured when built.

## Consequences

- An extension author writes one JSON interface and chooses the route; ask carries one more adapter, not a second protocol.
- Third-party compiled extensions need re-signing by whoever builds ask. That is a real cost, and the price of keeping library
  validation.
- Nothing here is built. The order: 0033's hook host first (the process route and `AgentHook`'s points), then this adapter. The first
  dylib comes once a measured case shows the process route over budget: 0190's index is the candidate.

## Questions for the owner

1. Keep library validation (third-party dylibs must be re-signed), or allow unvalidated dylibs in a build made for that?
2. Are tools from dylibs wanted at all while MCP serves tools at 20 to 36 µs a call, or is the dylib route for hooks and 0190's index
   only?
3. The `name.askext/` folder with a manifest, or a manifest read from the dylib itself, which needs loading it to list its tools?
