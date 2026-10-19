---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0020
---

# 0018 — Seatbelt for child processes

bash, and any later spawning tool, run under a Seatbelt profile compiled from the effective policy
(ADR-0020).

## What lands

- **An SBPL compiler for `SandboxPolicy`:**
  - a deny-default base for strict policies, Codex-style (`/dev/null`, `/dev/tty`, `/dev/ptmx`, `/etc`,
    system libraries);
  - an allow-default base with denials for permissive ones;
  - every path canonical and passed with `-D`, never interpolated.
- **bash runs `sandbox-exec -D … -p <profile> /bin/bash -c …`,** keeping group teardown.
- **Denials reported** as the policy in force plus "Operation not permitted". Reading Seatbelt's own
  violation records stays open until a probe shows how (`docs/research/sandboxing-2026-10.md`).
- **Integration tests per capability,** each proving the denial *and* its absence under a wider policy:
  - network off, localhost only;
  - writes confined;
  - reads denied;
  - children inherit.

## Measure

Spawn cost against unsandboxed bash; the probe says about +7 ms. The candidate improvement is a launcher
that calls `sandbox_init_with_parameters` and then `exec`, kept only if it measures faster.

## Done (2026-10-19)

ADR-0035. bash runs under `sandbox-exec` with the policy compiled to Seatbelt: paths as parameters, the
protections last, every ancestor of a protected path guarded against rename. Group teardown still reaches the
command. A refusal is followed by a note with the policy.

**Measured:** +8 ms per command (1.9–2.3 → 9.7–11 ms). The launcher candidate measured no faster and is
rejected. Integration tests run each probed attack beside the ordinary work that must still pass.
