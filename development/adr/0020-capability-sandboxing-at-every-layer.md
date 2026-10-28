---
status: accepted
date: 2026-10-19
---

# 0020 — Capability sandboxing at every layer, narrowing inward, widened only by the user

## Context

ask runs a model's commands and file edits on the user's machine. The user wants sandboxing that:
- separates capabilities: network, read and write, each local or by path;
- applies at any layer: ask started sandboxed, a session, one run, one bash call, one tool call;
- lets the model ask for a sandbox on each call, or for everything at once.

The evidence is in `development/research/sandboxing-2026-10.md`. Three probed facts shape the design:
1. **Seatbelt does not nest.** A sandboxed process cannot apply a narrower Seatbelt profile, through
   `sandbox-exec` or `sandbox_init` (exit 71). So the layer that applies Seatbelt is the last one that can.
2. **Seatbelt sees paths, IPs and ports, not domains.** Rules match canonical paths only and fail closed
   otherwise. Network can be off, localhost-only, or on, but never per domain.
3. **One Seatbelt profile covers a whole process.** ask's in-process tools (read, write, edit) cannot get
   a profile of their own without becoming child processes.

## Decision

**A policy is a set of capabilities:**
- `network`: `none`, `localhost`, `domains([…])` (through a local proxy, see 0021), or `any`;
- `read`: everywhere except denied paths, or only allowed paths;
- `write`: nowhere, the workspace, or listed paths.

A default deny list (credentials, keys, ask's own credential file) applies under any policy that allows
reads.

**Layers narrow, never widen.** The effective policy for a call is the intersection, from outside in:

```
ask process  ∩  session  ∩  run  ∩  tool call   =  effective
```

Any layer may narrow what it receives. Only the user widens: through a flag, configuration, or an approval
prompt. Never the model, and never automatically.

**Enforcement follows the probes.** In the default mode ask stays unsandboxed, like Codex and Claude Code,
because it must hold credentials, talk to the provider and write the session:
- **Child processes** (bash, and any later tool that spawns) run under Seatbelt with the effective policy,
  compiled to an SBPL profile:
  - paths are passed as `-D` parameters, which are data and cannot inject syntax;
  - paths are canonicalized with `realpath` first;
  - strict policies use a deny-default base, permissive ones an allow-default base with denials.
- **In-process tools** check the effective policy themselves, against canonical paths, before any I/O.
  Denials are outputs the model reads, naming the capability that refused.

**ask can be started sandboxed** (`ask --sandbox …`, roadmap 0020). It applies `sandbox_init` at startup
with the process layer's policy (provider network, session directory, credentials, and the workspace as the
policy allows). The probe's consequence is accepted and stated to the model and the user: in that mode,
narrower per-call Seatbelt is impossible. Children inherit the process sandbox, and per-call narrowing
falls back to the in-process checks where they apply.

**The model can propose sandboxing.** Every tool accepts an optional `sandbox` argument with the same
capabilities:
- a request that **narrows** applies atomically to that call, with no prompt;
- a request that **widens** beyond the session is never applied silently: interactively it becomes an
  approval prompt, and under `-p` it is refused unless the user's flags already allow it.

A session-wide proposal ("sandbox everything from now on") is a narrowing and needs no approval. Undoing it
is a widening and does. The system prompt states the active policy, and denials name the capability.

**Mechanisms are pluggable behind the policy.** Seatbelt on macOS now. Then a domain proxy (0021), and a
container or VM backend for whole-session isolation (Apple `container`, 0022). Linux's Landlock or
bubblewrap fit the same policy type when ask runs there.

## Consequences

- A sandboxed bash call costs about 7 ms more to spawn (probed). It is paid per call, off the input path,
  and is benchmarked when it lands. A launcher calling `sandbox_init_with_parameters` before `exec` is the
  recorded micro-optimisation candidate.
- `sandbox-exec` and SBPL are deprecated and undocumented. They still ship, and two other agents depend on
  them. Probes in `development/research` are re-run on each macOS release, and a failing probe is a release
  blocker for the sandbox, never a silent downgrade.
- Seeing *which* operation Seatbelt denied is unproven (the log query found nothing for our probes).
  Until a probe shows how, a denial is reported as the policy in force plus the command's
  "Operation not permitted" output.
- In-process checks are only as good as path canonicalization. Every path is resolved before the
  decision, and symlink races are named as a residual risk until file tools run in a sandboxed helper.
