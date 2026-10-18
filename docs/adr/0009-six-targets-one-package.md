---
status: accepted
date: 2026-10-18
---

# 0009 — Six targets, one package, with the provider layer as a leaf

## Context

`ask`'s manifest names six targets — `AskCore`, `AskTerminal`, `AskTUI`, `AskAgent`, `AskProviders`,
`AskCodeMode` — and only three exist. The manifest's own header comment describes them in one line each,
which is not enough to build against, and two of the six overlap: `AskAgent` is described as "agent loop,
tool execution, session persistence", which is three responsibilities.

The open question was whether that list is the right shape, and whether the fine grain is affordable
against a 25 ms cold-start budget.

## The probes

**Probe 1 — what does the reference implementation actually do?** Read the package graph of
`earendil-works/pi` at `main` (11 packages) and the `dependencies` of each `package.json`.

**CONFIRMED as a useful shape.** The graph is:

| Package | Internal deps | Role |
|---|---|---|
| `pi-ai` | — | providers, model catalog, auth, protocol adapters in `compat/` |
| `pi-agent-core` | `pi-ai` | "General-purpose agent with transport abstraction" |
| `pi-tui` | — | terminal UI |
| `pi-codemode` | — | codemode host |
| `pi-mcp` | — | MCP |
| `pi-coding-agent` | agent-core, ai, codemode, mcp, tui | the app: read/bash/edit/write tools, sessions |
| `pi-durable` | chord, ai, codemode | durable conversations |
| `pi-env` | chord, durable | remote execution |

Three properties worth copying. **The composition root depends on everything and nothing depends on
it.** The provider layer is a **leaf with no internal dependencies**, so it cannot know about tools or
the agent. And **the loop is generic while the tools are the app** — `pi-agent-core` is described as
general-purpose, while read/bash/edit/write live in `pi-coding-agent`.

**Probe 2 — does module granularity cost cold start?** Built a scratch SwiftPM package with N trivial
targets linked into one executable, at N = 1, 5, 10, 20, release and WMO, then measured spawn-to-exit
interleaved over 40 rounds so background load cancels out of the ratio.

**REFUTED.** Medians 4.38 / 4.44 / 4.41 / 4.37 ms. Spread across all four: **0.067 ms** — inside noise.
Going from one target to twenty cost nothing measurable.

**Probe 3 — what does cost?** Same harness, three binaries.

| Binary | Spawn-to-exit, median | Binary size |
|---|---|---|
| `/bin/echo` | 2.05 ms | — |
| trivial Swift | 3.04 ms | 50 KB |
| `ask --budgets` | 4.59 ms | 694 KB |

So the Swift runtime is ~1.0 ms, and everything `ask` links — TerminalKit, Aemi, swift-collections,
AemiKernel — is about **1.55 ms**.

## What the probes refute, including in our own documents

**The white paper states: "Startup cost is paid once per process, so every linked module is paid for at
every launch."** Probe 2 says the module half of that is not measurable at this scale. The *link weight*
half stands and is what Probe 3 measured.

The principle is corrected in `docs/WHITE-PAPER.md` rather than left standing, because a wrong principle
outlives the investigation and gets cited as a reason to avoid fine-grained modules forever.

**Scope of Probe 2, stated honestly:** trivial modules with no static initializers, no globals and no
Objective-C classes, measured spawn-to-exit rather than spawn-to-first-frame. A module carrying heavy
initialisation is not covered, and is exactly the kind of thing that would make the claim true. The
finding is that module *count* is free, not that module *content* is.

## Decision

**One package, six targets, composed like pi's graph.**

```
AskCore        budgets, session identity, documentation layout      (no internal deps)
AskAI          providers, streaming, protocol adapters, catalog,
               auth, request construction          deps: AskCore     [LEAF within the package]
AskAgentCore   the loop, turn management, session tree,
               context construction                 deps: AskAI
AskTools       the Tool protocol's implementations —
               read, write, edit, bash              deps: AskAgentCore
AskTUI         screen model, widgets, input routing deps: TerminalKit only
AskCodeMode    the codemode host                    deps: AskAI, AskTools
ask            composition root — the only target that sees everything
```

## Why one package rather than six

The reason TerminalKit is its own repository is independent release cadence: the fastest-moving work
should not wait on a repository with no releases (ADR-0005). Every one of `ask`'s six targets ships in
the **same binary on the same day**, so none of them has independent cadence to protect. Splitting them
into packages would add six manifests to maintain and buy nothing — and Probe 2 removed the cold-start
argument that would otherwise have been raised against fine targets.

One package, many targets, is therefore correct here, and it is what the white paper already said.

## Why the loop splits from the tools, without becoming generic

pi splits them because plugins consume the loop without the tools. `ask` has no plugin system, and
building a generic loop now would be speculative generality, which the white paper bans.

The split is still worth making, for two reasons that are not about reusability:

- **Different test surfaces.** The loop is driven by a mock provider; the tools are driven against a real
  filesystem and a real subprocess. They need different test targets and different doubles.
- **Codemode needs tools without the loop's turn machinery.** `AskCodeMode` depends on `AskAI` and
  `AskTools`; if the loop and the tools were one target, codemode would inherit turn management it has no
  use for.

The loop stays coding-specific. If a plugin system ever appears, the split is already in place.

## Where the Tool protocol lives

In `AskAgentCore`, not in `AskTools`. The loop dispatches tools, so it owns the contract; `AskTools`
implements it; `AskCodeMode` calls it without caring which is which. Putting the protocol in `AskTools`
would invert that and make codemode depend on an implementation.

## Where the Claude gate lives

In the `AskAI` request adapter, not in the agent. ADR-0007 established that the gate constrains *request
construction* — the system param must be one canonical block, and harness content must ride in user
messages. That is a wire-format constraint, so it belongs with the wire format.

The agent's context builder stays unaware of it and produces ordinary messages; the adapter relocates
them. That keeps the gate out of the loop, which means a Spettro request never pays for it.

## Consequences

- `AskTerminal` from the manifest's header comment disappears. Its two stated jobs — capability
  negotiation and the reset ladder — are TerminalKit's and `0003`'s, not a separate layer in `ask`.
- The manifest's header comment is rewritten to match, since it currently describes targets that will not
  exist.
- Access control becomes the enforcement mechanism rather than a convention: `internal` by default means
  a target cannot reach another's internals, so the graph is checked by the compiler rather than by a
  review.
- Six targets against 17 tests means most targets have no tests yet. That is the honest state and is
  recorded rather than smoothed over.

## Follow-ups

- `0013`'s renderer adoption decides whether `AskTUI` stays one target or splits into screen model and
  widgets. Not decided here.
- Whether `AskAI`'s protocol adapters deserve their own target, mirroring pi's `pi-ai/compat`, is
  undecided. It is defensible either way and depends on how much the two protocols' differences grow.
- The white paper's correction is applied, but the *benchmark* that maintains it — module count against
  cold start — does not exist in CI. A principle with no guard drifts back.