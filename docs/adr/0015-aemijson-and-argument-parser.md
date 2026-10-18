---
status: accepted
date: 2026-10-18
---

# 0015 — AemiJSON owns JSON; swift-argument-parser owns the command line

## Context

`SessionLog` used Foundation's coders, and `ask` parsed its one flag by hand from
`CommandLine.arguments`. Provider streams, tool arguments and a real command line are all ahead, so the
owner of each concern needed choosing before it was written several times over. The user chose AemiJSON
for JSON and Apple's `swift-argument-parser` for the command line.

A dependency is an architectural decision and is paid for at every launch, so both were measured before
adoption, not after.

## Probes

**Graph compatibility.** AemiJSON pins Aemi `a6446f1`, and SwiftPM refuses two revisions of one package
in a graph. TerminalKit had already moved to that revision, so ask repinned TerminalKit to `98650f4` first.
AemiJSON also caps `swift-collections` below 1.7.0, which drops resolution from 1.7.3 to 1.6.0. Its
manifest's stated reason is that 1.7.x needs a runtime macOS 26 lacks; that would matter on our floor, but
it was not reproduced here.

**Behaviour.** The wire format stayed byte-identical: both golden tests passed unchanged. A path test was
added after a mutation enabling slash escaping went uncaught. AemiJSON's `nilStrategy: .omit` affects only
`encodeIfPresent`, so the explicit `null` leaf record survives.

**Cost.** Interleaved over a PTY, spawn to first prompt, 30 rounds for cold start and 5 for RSS:

| Binary | Cold start (median) | Idle RSS | Size |
|---|---|---|---|
| before | 4.43 ms | 5840 KiB | 0.86 MB |
| + argument-parser | 6.04 ms | 6768 KiB | 2.38 MB |
| + AemiJSON as well | 6.57 ms | 6928 KiB | 4.69 MB |

The runtime cost is mostly argument-parser, about 1.6 ms and 0.9 MiB resident. AemiJSON costs mostly
binary size, 2.3 MB, and little at runtime.

## Decision

1. **All JSON goes through AemiJSON**, named qualified (`AemiJSON.JSONEncoder`) so Foundation's coders
   cannot be picked up by accident. `encodeToBytes` and `decode(_:from: [UInt8])` remove the `Data` round
   trip at both edges. `AskAgentCore` no longer imports Foundation.
2. **The `ask` executable parses its command line with `swift-argument-parser`.** `--help` works, and an
   unknown flag now exits 64 with a usage message instead of being ignored.
3. **The `--budgets` report is AemiJSON-encoded** in `AskCore`, and a test pins the four keys
   `Scripts/measure-budgets.py` reads.
4. **`SourceStandards` enforces both**: `JSONSerialization`, unqualified `JSONEncoder(`/`JSONDecoder(`, and
   `CommandLine.arguments` fail the suite. Each rule was probed with a violation that compiles.

## Consequences

- Both choices fit the budgets: cold start 6.6 of 25 ms, idle memory 6.8 of 8 MiB.
- **Idle-memory headroom drops to about 1.1 MiB**, before the agent loop, providers and tools exist. That
  budget was set over an agent-less binary and will need re-deriving alongside the action-to-action budget
  (roadmap 0007), on measurements, not on this entry.
- Argument-parser's resident cost is larger than expected for one flag. If memory becomes the binding
  constraint, it is the first place to measure, not the first thing to remove.
