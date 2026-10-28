---
status: accepted
date: 2026-10-20
---

# 0054 — A tool call may narrow its own sandbox, and never widen it

## Context

ADR-0020 decided that the model may propose sandboxing: every tool accepts an optional `sandbox` argument with the same
capabilities as the policy; a narrowing request applies to that call, and a widening one is never applied silently.
Roadmap 0019 delivers it. Strict modes (ADR-0043) and the read allow-list (ADR-0047) gave the policy the capabilities to
narrow.

## Decision

- **The argument.** `bash`, `read`, `write` and `edit` declare an optional `sandbox` object: `network` (none,
  localhost, any), `write` and `read` (lists of paths, absolute or relative to the working directory). `wait`,
  `job_input` and `job_stop` do not: they act on jobs that already run under the sandbox they started with.
- **Applied at dispatch.** `ToolRegistry.run` resolves the request against the run's policy before the tool runs. Each
  dimension that is narrower narrows that call: the network level, the write roots, the read roots (which on an
  unrestricted run switch that call to the deny-default read base). Protections are untouched.
- **Asking for more is refused, not trimmed.** A network level above the run's, or a write or read root outside what the
  run allows (scratch and, for reads, the system's directories always count as allowed), makes the call not run. The
  result names every such request and says only the user can widen the sandbox. A malformed request also does not run.
  Silently trimming a widening would run something other than what the model asked for.
- **Not yet:** an approval prompt that lets the user grant a widening, once or for the session, and the model narrowing
  the whole session. Both are roadmap 0019's next slices. Under `-p` a widening stays refused; the `--network`, `--write`
  and `--read` flags (ADR-0043) are how the user widens there, so 0019's proposed `--sandbox` flags are not added.

## Probes

Unit tests of the rules; registry tests that the tool sees the narrowed policy or does not run; real `sandbox-exec` tests
in a home outside scratch. Real-binary probe U: a call narrowed to no network cannot reach a local server the run can;
narrowed to a subdirectory it cannot write beside it; the read tool narrowed to the workspace cannot read elsewhere; a call
asking for network beyond `--network localhost` is refused with the explanation; the request to the model declares the
argument. Eight compiling mutations caught (diary 49).

## Consequences

Each request's tool list grows by about 1.4 KB (four schemas of 346 bytes), cached by the provider. Decoding the argument
on every call costs nothing measurable: the action budget was 2.5–2.8 ms p50 with it and 2.9–3.0 ms without, in
alternating rounds (no speedup claimed).
