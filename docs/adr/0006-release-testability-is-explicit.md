---
status: accepted
supersedes: ADR-0002
date: 2026-10-18
---

# 0006 — Optimized tests can explicitly enable testability

## Context

ADR-0002 concluded that release testing makes `@testable` impossible. Subsequent guidance also
claimed timing `unsafeFlags` disabled testability. Both conclusions conflated commands with
different defaults. The original failure used a release **build** command, not an explicitly
testable **test** command.

## Evidence

TerminalKit ADR-0012 contains the controlled reproduction on Apple Swift 6.4:

- `swift build --build-tests -c release`: incompatible-module error at the codec's `@testable` import.
- `swift test -c release --enable-testable-imports`: the same test passes and the library compiler
  receives `-O -whole-module-optimization -enable-testing`.
- `--disable-testable-imports`: the error returns.
- Reinstating both original timing `unsafeFlags` with testability enabled: still passes.

Apple-docs MCP, `swift-evolution/0455-swiftpm-testable-build-setting`, describes the release
default and explicit CLI override. Neither metadata-emission changes nor public API widening
was needed.

## Decision

Public-API behavior tests remain preferred. Internal tests are allowed when justified; select
`swift test -c release --enable-testable-imports` explicitly in the quality gate.

Build shipping executables and benchmark binaries separately without testability. Enabling
internal visibility can affect code generation; an optimized test build is not claimed to be
byte-identical to a shipping build. Benchmarks continue to target the latter.

The false blanket timing-flag ban is removed. `ask` currently retains its expression type-check
warning, which measures compile time, not runtime latency. It is not changed by this correction.

## Consequences

The previous policy no longer prevents moving the terminal's owning tests into TerminalKit.
No production declarations need to become public to make those tests compile.
Probe details live in TerminalKit's diary and ADR-0012; the white papers carry only the corrected
build/testing principle.
