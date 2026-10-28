---
status: not-started
blocked-by:
date: 2026-10-19
decision: ADR-0020
---

# 0020 — Run ask itself sandboxed

`ask --sandbox …` applies `sandbox_init` at startup (ADR-0020), for users who want the whole agent
confined.

## The profile

- Network to the provider (Seatbelt cannot name domains: HTTPS out, or localhost when a proxy is used).
- Reads of the credential file and the session directory, and writes to the session directory.
- The workspace, as the chosen policy allows.

## The probed consequence, stated rather than hidden

Seatbelt does not nest, so in this mode bash calls cannot be narrowed further with Seatbelt. They inherit
the process sandbox. Per-call narrowing falls back to the in-process checks, which do not cover a child's
own syscalls. The system prompt and `ask --help` say so.

## Done when

A probe shows the sandboxed ask can still sign in, stream, write its session and run tools, and cannot
read a denied path or write outside its policy, from the agent or from any child.
