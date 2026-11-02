---
status: not-started
blocked-by: ["0192 hook points", "0033 process host"]
date: 2026-10-29
---

# 0140 — Compiled plugins loaded at run time, for hooks that must be fast

Owner wish (2026-10-29 10:12): "Among hooks, potential extensions and other mcp tools we could investigate ways to link or enable ask behaviour changes
and hooking with compiled plugin we could link and load dynamically, interesting for performances, not a huge priority, but interesting to solve as a
technology aspect".

## Where it fits

ADR-0123: tools from outside arrive through MCP, and the extension host (0033) is for hooks only. A compiled plugin would be a second transport for the
same hook points, `dlopen` of a dylib in process rather than JSON-RPC over stdio. It is not a third route for tools.

## Questions to settle before building

- **The cost to beat.** Measure one stdio JSON-RPC round trip per hook call against the 4 ms input and 8 ms action budgets. If the subprocess fits, the
  plugin buys nothing.
- **The ABI.** Swift has no stable ABI across compilers for a plugin's own types. A C entry point (`@_cdecl`) taking and returning bytes (the same JSON
  as 0033, or a fixed binary layout) keeps the plugin free of ask's types and its Swift version.
- **The sandbox.** Code in process runs with ask's rights, outside the Seatbelt profile the tools get. Loading one is the owner's explicit consent per
  path, as for widening the sandbox, and macOS library validation (hardened runtime) refuses unsigned dylibs unless ask is entitled otherwise.
- **Unloading and reloading.** `dlclose` is not dependable for Swift images, so `/reload` re-execs ask, as it does now.

## Done when

A measured hook that a subprocess cannot serve within budget, an ADR choosing the entry point and the consent, and one plugin loaded, called and refused
when unsigned, with tests. Not before 0033's hook points exist.

## Owner (2026-11-01, ideas i3 and i2): a dylib platform beside MCP

- A developer extends ask with dylibs for high-performance features; the first surface is tools, LSP servers and hooks.
- **Beside MCP, not instead of it:** a dylib is one more source of tools, as MCP servers and ask's own are. ADR-0123 keeps the
  child-process host for hooks; this entry's in-process route is the fast one for all three surfaces. A design record says how the two
  hook routes relate.
- Owed, in the design record before code: the binary interface (a C entry point and a versioned table: Swift has no stable binary
  interface for this), code signing and library validation under the hardened runtime, trust per project as for skills and MCP, what
  the sandbox means for code that runs inside ask, and the cold-start budget (a library loaded on first use, not at launch).
- The first consumer is 0190 (a Swift edition), whose swift-search tool would be such a dylib.


## Design (2026-11-02, revised with the owner's answers; becomes ADR-0142 once accepted)

Nothing is built. The owner's answers (2026-11-02):

1. Do not require re-signing a third party's dylib.
2. Tools and hooks, but first design where hooks attach: roadmap 0192.
3. The manifest: refine it.

### Context

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
  ask's team, and ignores `DYLD_INSERT_LIBRARIES` and its kin. An ad hoc build (no identity) has no library validation.
- **Swift has no stable binary interface** between a plugin's compiler and ask's for Swift types. `dlclose` is not dependable for Swift
  images.
- **Trust today** is per file as it is now (`trusted.json`, a hash): a project's skills, configuration and MCP servers load only once
  trusted.

### Proposal

1. **One C entry point, one versioned table.**
   - The dylib exports `ask_extension_v1(const ask_host *host) -> const ask_extension *`, written in C or as a Swift `@_cdecl`.
   - The host's table holds the version, the table's size, `log`, and `done(token, bytes, length, failed)`.
   - The extension's table holds the version, the size, `describe() -> bytes`, `call(token, kind, name, bytes, length)` and
     `cancel(token)`.
   - Calls finish through a callback. `call` returns at once, and the extension calls `done` from any thread when it has the answer.
     ask turns that into a continuation, so a slow tool never holds a thread of Swift's cooperative pool. `cancel` comes from Esc.
   - Bytes are valid only during a call. ask copies what `done` hands it before `done` returns, so nobody frees the other's memory.
   - The bytes are the JSON that already exists: MCP's `tools/call` for a tool, and 0192's hook messages for a hook. The same extension
     can ship as a dylib or as a process, and ask adapts both with the code it has.
   - A newer table only adds fields at the end. ask reads `size`, and refuses a version it does not know, by name, in the transcript.
2. **A folder with a manifest: `name.askext/`.**
   - It holds `extension.json` and the dylib. User extensions sit in `~/.config/ask/extensions/`, a project's in `.ask/extensions/`.
   - The manifest holds `abi` (1), `name`, `version`, `library` (the dylib's file name), and:
     - `tools`, each with `name`, `description`, `inputSchema` and `readOnly`;
     - `hooks`, each with `point` (0192), `deadlineMs`, `onFailure` (`open` or `closed`), and an optional `match`. For example
       `{"tools": ["bash"]}` means it is called only for those tools.
   - **Nothing loads at launch.** Tools are offered from the manifest, and `match` decides whether a hook needs the dylib at all. The
     dylib is loaded at the first call that needs it, after the first frame if a hook wants `session.start`.
   - **The manifest is checked against the code.** At load ask calls `describe()`. If its tools and hooks differ from the manifest, the
     extension is marked broken: its tools say so, and its hooks fail as each one declared.
   - A tool whose name clashes with one of ask's or an MCP server's is not offered. ask names the clash.
   - A setting turns an extension off by name: `extensions.<name>.enabled`.
   - Later: an `AskExtensionKit` package with the `@_cdecl` glue and a build plugin that writes the manifest from the declared tools,
     so the two cannot drift.
3. **No re-signing, so trust is the gate.**
   - A signed ask carries `com.apple.security.cs.disable-library-validation`, and keeps the rest of the hardened runtime. `DYLD_*`
     variables stay ignored, so no other process can push code into ask. Only a path ask chooses to `dlopen` can be loaded.
   - ask chooses only trusted copies. At load it copies the dylib into `~/Library/Caches/ask/extensions/<sha256>.dylib`, in a 0700
     folder, hashes the copy, and loads the copy only if that hash is trusted. A file swapped after it was trusted is therefore never
     loaded.
   - Apple silicon needs at least an ad hoc signature, which the linker adds by default.
4. **Trust per extension, by the hash of its manifest and dylib together.**
   - A user extension is asked about once, at its first use.
   - A project's extension waits until the project is trusted, and is then asked about on its own.
   - Any change to either file is asked about again.
   - The prompt says plainly that the code runs inside ask with ask's rights: its files, its network, and the Keychain items ask
     holds, such as provider keys.
5. **No sandbox inside the process.** Seatbelt applies to a whole process. So a dylib runs with ask's full rights, and with its
   network, files and Keychain. Therefore:
   - its tools are refused in a narrowed session, as MCP tools are (`MCPToolAdapter.narrowedRefusal`);
   - its hooks still run there, since a hook can only block or rewrite;
   - a dylib that crashes takes ask down with it. This is why **the process route stays the default**, and the dylib route is for
     extensions whose authors measured the need.
6. **Hooks have two routes and one meaning.** 0192 defines the hook points once, in `AgentHook`. A process extension and a dylib reach
   them through two adapters, with the same JSON and the same fail-open or fail-closed rule. A dylib whose call does not return
   within the hook's limit cannot be killed. It is then stopped from being called again, and the transcript says so.
7. **LSP servers stay processes.** A language server is a process by its protocol, and sourcekit-lsp ships as one. A dylib extension can
   offer language tools (definition, references) over its own index; it is not a way to load an LSP server.
8. **Budgets.** A loaded dylib's memory counts in ask's RSS budgets (15 MiB idle, 20 MiB active), so a large index belongs in a process.
   The load happens on first use, inside that call's action budget, and is measured when built.

### Consequences

- An extension author writes one JSON interface and chooses the route; ask carries one more adapter, not a second protocol.
- Turning library validation off is a real loss. A trusted extension can read ask's provider keys, and nothing but the person's trust
  stops a malicious one. The trust prompt has to say that, every time.
- The order: 0192's hook points, then 0033's process host, then this adapter. The first dylib is 0190's index.

### Not verified

- Whether Gatekeeper refuses a quarantined, unnotarized dylib that a process without library validation loads with `dlopen`. If it
  does, the trust prompt would offer to remove the quarantine, saying so; ask never removes it silently.
- The load's cost against the action budget.
