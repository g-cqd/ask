---
status: accepted
supersedes: ADR-0004
date: 2026-10-18
---

# 0005 — `ask` will depend on TerminalKit, not on a terminal tier inside Aemi

## Context

ADR-0004 decided that the terminal stack would become a group of targets inside Aemi's single package,
after probing corrected the scope from three modules to six. While that was being carried out, the
placement itself was questioned, and the question was put rather than assumed away.

## The probes

**Probe 1 — is terminal one of Aemi's existing categories?** Aemi's manifest describes the package as
the kernel package and splits its targets into kernel runtime tiers (`AemiKernel`, `AemiText`, `AemiIO`,
`AemiMetrics`, `AemiRuntime`, `AemiUnicode`, `AemiKernels`, `AemiMacroSupport`) and application tiers
(`AemiCore`, `AemiUI`, `AemiTesting`), keeping the two deliberately apart.

**REFUTED as a fit.** Terminal is a third category — an escape-sequence grammar, a capability
negotiation, a reset lifecycle. Containing it stretches a boundary Aemi already defends.

**Probe 2 — what does a consumer of `AemiKernel` resolve?** Aemi declares five direct dependencies:
**swift-syntax 603..<605**, swift-collections, swift-system, swift-docc-plugin, benchmark. SwiftPM
resolves a package's whole manifest regardless of which target is linked.

**CONFIRMED, and deliberately not overstated.** `AemiKernel` is zero-dependency, but a consumer still
resolves the swift-syntax macro tree. Separating the terminal does not remove that cost, because
`KittyCodecs` and `KittyInput` genuinely import `AemiKernel` and TerminalKit will depend on Aemi. The
gain is independent cadence and a focused manifest — **not** independence from Aemi.

**Probe 3 — is Aemi a steady release target?** `git tag` returns **zero tags**.

**CONFIRMED.** The fastest-moving work in the ecosystem should not wait on a repository with no
releases.

## Decision

`ask` depends on **TerminalKit**, a repository of its own, for the terminal stack, and on **Aemi** for
the kernel tier and the deterministic test kit. Two focused dependencies, each with one job.

ADR-0004's scope measurement — six modules, 6,263 lines, measured by following the import closure
rather than by reading module names — is unchanged and still correct. Only the destination moved.

## Consequences

- The reset ladder and its oracle moved out of Aemi within hours of landing there (`03ac1d5`, `e86d8fd`
  in, `d0f8108` out). A few hours of churn bought a placement that is defensible rather than
  convenient.
- **TerminalKit has no GitHub remote yet.** Until one exists, `ask` can only reach it by a local path
  dependency, which does not ship. Creating a remote is the next blocker, not an afterthought.
- `ask` will depend on Aemi by pinned revision, as Atelier already does — not by tag. Aemi having no
  tags is a real wart, but it is not a blocker, and ADR-0001's claim that it was one has been
  corrected.
- Two repositories now carry the documentation law, and each enforces it with its own tests. The laws
  are identical; if they ever diverge, that is a defect in both.