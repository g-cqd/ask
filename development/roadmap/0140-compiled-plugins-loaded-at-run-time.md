---
status: not-started
blocked-by: ["0033 hook points", "a hook whose cost a subprocess cannot meet"]
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


## Design record (2026-11-02, ADR-0142, proposed)

- **Measured cost to beat:** a stdio JSON-RPC call is 20 to 36 µs (0114), under 1% of the input budget. Latency alone does not justify a
  dylib. Large state on every call, shared memory (0190's index) and per-event hooks might.
- **Proposed:**
  - a C entry point `ask_extension_v1` with a versioned table, carrying the same JSON as MCP's `tools/call` and 0033's hooks;
  - a manifest beside the dylib, so it loads on first use, never at launch;
  - library validation kept, so only dylibs signed by ask's team load in a signed ask;
  - trust per dylib by its code-directory hash;
  - its tools refused in a narrowed session;
  - LSP servers stay processes;
  - the process route stays the default.
- Waiting on the owner: three questions at the end of ADR-0142. Building waits on 0033's hook host.
