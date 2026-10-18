---
status: accepted
supersedes: ADR-0012
amends: ADR-0013
date: 2026-10-18
---

# 0014 — The bar is our own: reliable, fast, light, convenient

## Context

ADR-0012 framed ask's behaviour as divergences from pi, and ADR-0013 justified session recovery as "at
least as convenient as pi". Within a day the codebase carried 31 test comments and two source comments
naming pi, test doc comments beginning `Diverges from pi`, and probe scripts in `Scripts/`.

The user rejected that framing: ask should give a better experience overall, more reliable, faster and
lighter, and divergence from another agent is not the thing to focus on.

## Decision

1. **Requirements are stated in ask's own terms.** The white paper's reliability principle replaces
   ADR-0012's: damage costs only what is actually damaged, everything intact loads, every repair is
   reported, reading never writes, and refusing input needs a written safety reason.
2. **Code and tests state their own reasons.** No `Diverges from <agent>` markers, and no other agent named
   in sources or tests. A behaviour is justified by what it does for the user.
3. **Studying other agents is research, and it lives in `docs/research/`.** Running their code against edge
   cases remains how they are studied, since the probes found real issues that reading missed. Notes and
   probes are kept there, nothing is filed upstream, and nothing in the codebase depends on them.
4. **ADR-0013's decision stands on its own merits.** Damaged sessions load by default because one bad
   line must not cost a session, not because another tool does something similar.

## Consequences

- `Sources/` and `Tests/` name no other agent. `rg -i '\bpi\b' Sources Tests` returns nothing.
- The research note `docs/research/pi-1.3.0-findings.md` and its three probes keep what was learned.
- ADRs and diaries written before this keep their wording; they are history, and this record supersedes
  them rather than rewriting them.
