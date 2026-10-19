---
status: not-started
blocked-by:
date: 2026-10-19
decision: ADR-0035
---

# 0042 — Configure the rest of the sandbox, and the strict modes

The policy and the Seatbelt compiler already support more than anything configures: a write scope, a network
level, and (in the policy) the algebra to combine them. Today only the default protections and the `sandbox`
section's `allowRead` and `denyRead` are reachable.

## The work

- **Config keys** for the write scope (`workspace`, or a list of paths) and the network (`none`,
  `localhost`, `any`). Both narrow, so a project's file may set them; the user's file and flags may widen.
- **A read allow-list**, which needs a deny-default Seatbelt base in the style of Codex (`/dev/null`, `/dev/tty`,
  `/etc`, the system and Homebrew libraries). Probe what a Swift toolchain needs before promising it.
- **Record the policy in the session**, so a resumed session keeps its sandbox even when the flags differ.
- **Show the strict modes honestly in `ask config` and the status line.**

## Done when

A run confined to its workspace and localhost can build a Swift package (or says exactly which path it needed),
and a probe on the real binary shows each key narrowing and nothing widening from a project.
