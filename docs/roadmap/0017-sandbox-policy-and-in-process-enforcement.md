---
status: not-started
blocked-by: 
date: 2026-10-19
decision: ADR-0020
---

# 0017 — The sandbox policy, and enforcement in the file tools

ADR-0020's core: the `SandboxPolicy` type and the rules every other sandbox entry builds on.

## What lands

- **Capabilities:**
  - `network`: `none` / `localhost` / `domains` / `any`;
  - `read`: deny list or allow list;
  - `write`: none / workspace / paths.
- **Intersection,** which narrows only, with a test that no combination widens.
- **Path canonicalization** (`realpath`, symlinks, `..`) before any decision; a path that cannot be
  resolved is denied.
- **The default deny list:** `~/.ssh`, `~/.aws`, `~/.config/ask/credentials.json`, keychains,
  `~/.gnupg`, and others.
- **read, write and edit check the effective policy** before I/O. A denial is an error output naming the
  capability and the path.
- **The session records its policy,** so a resumed session keeps its sandbox.

## Done when

The file tools refuse what the policy forbids, every refusal names its capability, and mutation testing
shows no path or capability check can be dropped unnoticed.
