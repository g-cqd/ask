---
status: superseded
superseded-by: ADR-0006
date: 2026-10-18
---

# 0002 — Release-only builds, and therefore no `@testable`

> Superseded by ADR-0006. Release tests can enable testability explicitly. This record
> confused the defaults of `swift build` with what `swift test` can request.

## Context

`ask` exists to be fast, so `swift build` and `swift test` run `-c release`. A debug build measures a
program nobody ships, and benchmarking one is banned by the performance doctrine in the white paper.

This collided with Swift Testing practice. The first test target used `@testable import AskCore` and
failed to resolve the module in release.

## The probe

Two builds of the same test target, unchanged except for configuration:

| Configuration | Result |
|---|---|
| `swift build -c release --target AskCoreTests` | `unable to resolve Swift module dependency to a compatible module: 'AskCore'` |
| `swift build -c debug --target AskCoreTests` | `Build complete!` |

The strict flags were cleared as a cause before this was checked: removing each of the five upcoming
features one at a time still produced the identical failure, and so did reducing the whole set to
`.swiftLanguageMode(.v6)` alone. So the flags were never implicated.

## Decision

The cause is that SwiftPM passes `-enable-testing` only for debug builds, so `@testable` has nothing
to attach to in release.

**`ask` does not use `@testable`.** Tests exercise the public API only, and run in the shipping
configuration.

## Consequences

- Tests exercise the public surface, which is the surface that ships. A test that reaches past it is
  testing something no caller can use.
- Tests measure the configuration that runs in front of a user.
- A test needing internal access must instead be written against the module boundary it is really
  describing — usually that means the boundary is wrong.
- The alternative, forcing `-enable-testing` into release, was rejected: it changes what the optimiser
  may do and weakens the guarantee that the tested build is the shipped build.