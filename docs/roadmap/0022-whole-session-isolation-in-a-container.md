---
status: not-started
blocked-by: ["0017"]
date: 2026-10-19
decision: ADR-0020
---

# 0022 — Whole-session isolation in a container (research)

The strongest layer: run a session's tools inside a lightweight VM with the workspace mounted, using Apple's
`container` (1.5.0 is installed here, API server not running).

## To probe before any design

- Startup cost per session.
- File-system performance through the mount.
- Toolchain availability inside the guest. It is Linux, so macOS tools are absent.
- Whether per-call isolation is feasible, or only per session.

Linux hosts would use Landlock or bubblewrap behind the same policy type.
