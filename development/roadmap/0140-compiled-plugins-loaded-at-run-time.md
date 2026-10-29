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
