---
status: accepted
date: 2026-10-18
---

# 0011 — Use swiftlang/swift-subprocess for production child execution

## Context and inspection

The user identified the official Swift package as the preferred production subprocess mechanism.
The Apple-docs MCP lookup failed with HTTP 530, so the locally available official source was read:
AtelierCore's `swift-subprocess` checkout at `b3937ab85dd32f6e9435914599c1519074769c1a`
(`git describe`: `1.0.0`), its complete README and manifest, plus Atelier's `ProcessSession.swift`.
This is source/documentation evidence, not a new runtime or performance result.

The inspected manifest requires Swift 6.2 and macOS 13, below ask's Swift 6.4/macOS 26 floor.
It depends on swift-system and its internal C shims. `SubprocessFoundation` is an optional trait,
enabled by default; byte-oriented APIs do not require Foundation conversions.

Atelier already uses `Subprocess.run` for long-lived stdio sessions. Its adapter uses an actor,
an unstructured lifetime task and an unbounded output stream. Those policies are not automatically
appropriate for ask; reusing knowledge does not require linking AtelierCore or copying that wrapper.

## Decision

Use `swiftlang/swift-subprocess` behind an injected process-execution interface for production bash,
tool commands and future stdio services. Do not create a parallel Foundation.Process, posix_spawn,
fork/exec or DispatchQueue-based launcher in ask. Keep structured `Subprocess.run` ownership around
the child's whole lifetime; its Execution, output sequences and stdin writer must not escape the
run closure. Use nonisolated value types and structured concurrency; an actor must solve a concrete
async invariant rather than merely wrap a subprocess call.

Add the dependency with the first executable tool slice, not as an unused manifest entry now.
Pin the exact tested release/revision and record resolution then; the inspected checkout is a baseline,
not a claim about the latest release. Audit existing shared utilities before adding an application
wrapper; promote genuinely generic policy-free helpers to Aemi, without depending on Atelier.

## Consequences and validation gates

- Stream/drain stdout and stderr concurrently. Output caps must not create pipe deadlocks.
- The official collected-output `.bytes(limit:)`/`.string(limit:)` API **throws on overflow**.
  That is not ask's planned head/tail truncation plus full-output file. Implement bounded streaming
  collection/spooling as tool policy, with a separate disk ceiling; do not describe overflow as success.
- Configure teardown explicitly: cancellation, graceful shutdown and eventual forced termination.
  Verify descendant/process-group behavior; the docs are not proof every descendant is reaped.
- Validate executable/arguments, cwd and environment. Use an argument vector for ordinary tools;
  use an explicit noninteractive shell only when the tool is intentionally a shell command.
- Test with injected runners and event-driven probes/TestClock. Integration fixtures must cover
  simultaneous stdout/stderr, chunked UTF-8, overflow, spawn failure, nonzero exit, cancellation,
  ignoring SIGTERM, stdin backpressure and child reaping. Avoid sleeps and Task.yield.
- Measure shipping-binary startup/RSS and real tool-to-result latency before calling this lighter
  or faster. No such comparison has run yet.

Python PTY probes, shell quality scripts and TerminalKit's isolated C signal-safety probe are test
infrastructure, not the production subprocess implementation. The signal callback itself must stay
async-signal-safe; a subprocess library does not replace signal-handler safety.
