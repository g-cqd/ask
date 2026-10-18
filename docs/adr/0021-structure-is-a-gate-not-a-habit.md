---
status: accepted
date: 2026-10-19
---

# 0021 — Structure is a gate, not a habit: one type per file, provider code in its own directories

## Context

The complaint was that files kept growing and that the file listing hid the types the project owns. The
size half was already gated (SwiftLint `file_length`, 300 and 500). The hiding half was not, and nothing
could have noticed it: formatting and the metric lint measure a file, never what it contains.

Measured on 039bed1, 70 Swift files:

- **30 declared several types or did not carry their type's name.** Some held five or six (`FileTools.swift`
  held a namespace, a failure type and three tools; `HTTPTransport.swift` held six types).
- `Sources/` had 42 files for the types it owned, and the listing named roughly half of them.
- Provider code and the vocabulary it translates into shared one flat directory of 14 files in `AskAI`, so
  a second provider would have joined the first in the same pile, and `AskAgentCore` linked all of it.

## The probes

Full ledger in `docs/diary/2026-10-19-04.md`. The ones that decided this:

- **A four-type file passes every existing gate.** Committed through the pre-commit hook, SwiftLint and
  `Scripts/quality.sh` untouched. The gap was real, not assumed.
- **Two independent scanners agree** on which 30 files break the rule: a Python survey written first, and
  the Swift scan that became the gate. The same set, so the gate is not a model of itself.
- **Every new gate was broken on purpose and fired**, naming the file: a second type, a loosened helper
  exemption, a 251-line file, a provider name in neutral code, a clean file left in the baseline.
- **SwiftLint on `Tests/`** at the canonical thresholds reports 0 violations, so the exclusion hid no debt
  today. The ceiling below covers tests anyway, because the exclusion is a standing blind spot.

## Decision

1. **A file declares at most one top-level type, private or not, and is named for it.** Nested types are
   free, which is how a type used by exactly one other stays out of the listing. An extension in a type's
   file extends that type; any other extension lives in `Base+Topic.swift`, with one base per file. An
   extension whose every member is `fileprivate` or narrower is a helper nothing else can see, and is
   exempt. A file with no type may have any name.
2. **No file exceeds 250 lines**, sources and tests alike. The longest was 244 when this was adopted, so
   the ceiling blocks growth, not history. SwiftLint's wider limits stay as they are: that file is Aemi's
   canonical configuration and is synced, not edited here.
3. **Provider names stay inside provider code.** `Sources/AskAI/Anthropic` and `Sources/AskAI/Claude` own
   the wire protocol and the subscription sign-in; `Sources/ask` binds them. Every other directory,
   including `AskAI/Model` and `AskAI/Transport`, may not name a provider in code. A second provider is a
   new directory and a line in the composition root.
4. **Files are grouped by concern inside a target** (`Model`, `Transport`, `Anthropic`, `Claude`,
   `Support` in `AskAI`; `Loop`, `Tools`, `Session`, `Context` in `AskAgentCore`), so the tree reads as the
   architecture. Targets are not split further here: that is a link-weight question owned by ADR-0009.
5. **The rules are source scans in the `AskCoreTests` target and run in `swift test`**, so the pre-push hook, CI and
   `Scripts/quality.sh` all enforce them, and `SourceStructureTests` probes each rule. The scanner is in the test target, not `AskCore`, because `ask` links
   `AskCore` and a test-only scanner would ship; see the diary for what was measured.
6. **A ratchet baseline** (`SourceStructure.knownViolations`) holds files that break a rule today and are
   being edited by someone else at the time. A test fails when an entry is clean, so the list can only
   shrink. Anything not in someone else's uncommitted edits is fixed, not listed.
7. **Pre-push tests run in release.** `project-hooks` auto-detects a plain `swift test`, a debug build
   without explicit testability, which this project bans. `.project-hooks.yml` turns that stage off and
   runs the real invocation as a task, in the verification worktree at the pushed commit.

## Consequences

- Sources went from 42 files to 91. That is the point: the listing now names the types. It also means a
  reviewer opens more files; nesting is the release valve for genuine helpers.
- Splitting exposed coupling that `fileprivate` had hidden (`modelEvent`, `ProviderFailure.Kind.init(wire:)`,
  `leftPadded`). Those are now `internal`. Correct, and a reminder that file-private is also a way of not
  seeing a dependency.
- Under `InternalImportsByDefault` and warnings-as-errors, an unused `public import` is a **compile error**,
  so splitting a file means choosing each new file's imports. Periphery finds unused plain imports.
- Generic helpers (`Base64URL`, `FormEncoding`, `leftPadded`) stay in `ask`, in `AskAI/Support`: the
  decision here is not to move them. Aemi's `AemiKernel` has `Base64`, `Hex`, `PercentCoding`, `ByteSearch`
  which overlap; adopting them is an open question recorded in the diary, not a decision.
- Five files remain on the baseline (roadmap 0025). The gate also caught four source files and a test file in the interactive-screen commit that landed while this was being written; three were split, two were being edited and went on the baseline. The provider seam is gated by name only; whether it is
  *shaped* for a second provider is unprobed (roadmap 0026).
