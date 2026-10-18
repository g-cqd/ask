# ask — Project White Paper

The rules this project runs on. **Paste this at the start of every iteration.** An iteration that
cannot satisfy a rule below stops and fixes the rule, or asks to change it in writing — it does not
quietly proceed.

## Runtime principles

These are what "fast" is allowed to mean here. They bind every target in the ecosystem, and each one
excludes something that would otherwise look like an optimisation.

**A lightweight runtime.** A binary links only what it uses. No umbrella target that re-exports
everything, no speculative generality, no framework pulled in for one function. Startup cost is paid
once per process, so every linked module is paid for at every launch.

**Fewest allocations.** Allocation is not free and it is not only slow — it fragments, and a fragmented
allocator costs more in cache misses than the work that needed it. The hot path allocates zero times,
and a buffer is reused rather than re-made. Where a budget can be stated it is **measured and enforced
by a test**, because an allocation ceiling nobody checks is a wish.

**Close to zero copy.** Work in `ContiguousArray` and `UnsafeMutableRawBufferPointer` from the boundary
inward. No `Array`/`ContiguousArray` bridging, no `String` round-trip per keystroke, no copying a
buffer to append to it. Copy once, at the edge where data enters or leaves the process. Copy-on-write
is what a runtime reaches for when it cannot avoid a copy; here the aim is to have nothing to copy.

**Safest, and still near zero-copy.** These are requirements together, never a trade against each
other. No `-Ounchecked`, no disabled bounds or overflow checks, no `unsafe` that is not immediately
justified in a comment. The way to be both fast and safe is to **do less work** — diff a frame instead
of repainting it, reuse a buffer instead of allocating one, decode a byte once instead of re-scanning
it — not to remove the checks that catch the bugs.

**Every claim is measured.** A performance claim without before-and-after numbers, same harness, same
configuration, with units, is not a claim this project will act on.

**Generic tools belong in Aemi.** A tool that is not specific to one application does not live inside
that application. It is promoted to Aemi, the kernel package, and the specialised packages build on it
from there. This is not only about `ask`, TerminalKit, Atelier or KittyCode — it is a standing rule
for anything encountered anywhere in the ecosystem: if Aemi's scope would serve it better than a
single consumer's, it goes to Aemi. The test is whether a second consumer is plausible, not whether
one exists today.

The consequence is accepted rather than avoided: Aemi grows, and promoting something into it is a real
change to a package other projects depend on, so it is measured, reviewed and pinned by dependents
like any other.

---

## 0. The Evidence Rule

> **Every claim is challenged and backed by an actual probe before it is adopted or acted on.
> There is no place for an assumption.**

This is the first rule because every other rule here is downstream of it.

**What counts as a claim:** anything stated as fact about a toolchain, a protocol, a performance
number, a library's behaviour, a platform's guarantee, or someone else's code. If acting on it would
be expensive to undo, it is a claim.

**What counts as a probe:** running the thing and observing the result. A build, a test run, a
benchmark, a command's output, a `read` of authoritative documentation. A recollection of how a
tool "usually" behaves is not a probe.

**The probe protocol:**

1. **Name the claim.** Write it as a sentence that could be true or false.
2. **Design the probe** that would make it false if it is false. A probe that cannot fail proves
   nothing.
3. **Run it.** Record the command verbatim.
4. **Record the verdict** in the diary — claim, probe, result. Not here: this document
   changes when a principle changes, and a probe is not a principle.
5. **Act only then.** An unprobed claim is written down as an open question, never as a fact.

**Forbidden substitutes for a probe:**

- Confidence, experience, or "it is well known that…"
- A blog post, a second model, or documentation read out of context
- A passing build that does not distinguish between the hypotheses
- Inference from a *different* configuration than the one shipping

**The bisect lesson.** A flag blamed for a failure was cleared by removing it — from a build that
still failed, because four other flags were still present. The claim "flag X breaks the test target"
was false, and nearly became a written constraint. *A probe that cannot fail is not a probe.*

**Escalation.** When a probe contradicts a belief held confidently, the belief loses. Record the
contradiction in the diary. Do not re-litigate a settled decision unless new evidence contradicts it.

---

## 1. Red TDD

- **Red first.** A test is written, run, and observed to fail **for the right reason**, before the
  implementation exists. A test that has never failed has proven nothing.
- **One behaviour per test.** Named in backticks as a sentence:
  ``@Test func `every diary file is within the line budget`()`` — the name says what must hold, so a
  failure names its own cause.
- **Green by the minimum *general* code** — not code special-cased to the test's input.
- **Refactor with tests green**, one named move at a time.
- **Red and green land in the same commit.** History stays buildable and `git bisect` keeps working.
  The red is observed locally and recorded; it is not left broken on the main line.
- **Never** assert on nothing, never sleep or time out inside a test, never share mutable state
  between tests, never test a private method to test itself.
- Coverage is measured by **behaviour**, never by percentage.

## 2. Performance doctrine

- **No optimisation without a measurement showing the bottleneck, and a second measurement proving
  the fix.** Before/after, same harness, same inputs, same build configuration, with units.
- **Release only.** `swift build` and `swift test` run `-c release`. A debug build measures a program
  nobody ships. See ADR-0002.
- **Percentiles, not averages.** Users feel p95 and p99.
- **Budgets, stated as numbers.** The four `ask` budgets are cold start, idle memory, input delay,
  and action-to-action delay. Each is a number with units, recorded in the diary once measured.
  An unmeasured budget is not a budget.
- **Order of attack:** don't do the work → do less work → do it elsewhere → do it in parallel →
  micro-optimise last. Micro-optimisation without profiler evidence is banned.
- **Never trade correctness or safety for speed.** No `-Ounchecked` in this project, ever.
- Report median and spread, never the best run.

## 3. Swift package strictness

Verified against Swift Evolution on 2026-10-18. **Do not add a flag that is not in this table, and do
not remove one without a probe that shows the project is better without it.**

| Setting | Status | What it buys |
|---|---|---|
| `.swiftLanguageMode(.v6)` | Swift 6 | Complete strict concurrency. Also implies `RegionBasedIsolation`, `DisableOutwardActorInference`, `InferSendableFromCaptures`, `DeprecateApplicationMain` — the compiler *rejects* naming them as redundant, so `.v6` is what guarantees they stay on. |
| `StrictMemorySafety` | SE-0458, Swift 6.2 | SE-0458. The terminal stack moves bytes through raw pointers and POSIX descriptors; this is where an unchecked access becomes silent corruption. |
| `ExistentialAny` | SE-0335 | Every existential spells `any`, so intent is legible at the use site. |
| `InferIsolatedConformances` | SE-0470, Swift 6.2 | No unannotated conformance silently guesses its isolation. |
| `InternalImportsByDefault` | SE-0409, Swift 6.0 | An import grants internal visibility by default. **Consequence, probed:** any type in a module's public API needs `public import Foundation`. See the ledger. |
| `MemberImportVisibility` | SE-0444, Swift 6.1 | A member is visible only where its module is imported. |
| `.treatAllWarnings(as: .error)` | — | A warning is a defect with a louder voice. |

**Banned: `-warn-long-*`, as much as `-Ounchecked`.** A target carrying `unsafeFlags` is not built
with `-enable-testing`, so `@testable import` of it fails — a warning threshold silently costing the
ability to test the thing at all. A strictness flag that quietly removes a capability is not
strictness.

**Banned:** `-Ounchecked`. It strips the bounds and overflow checks `StrictMemorySafety` depends on,
trading correctness for a benchmark number.

## 4. Documentation law

- `docs/adr/NNNN-title.md` — **one decision per file**, stating context, decision, and consequences.
  A decision changed by new evidence is a **new ADR** that supersedes the old one; ADRs are not edited
  into an unrecognisable shape.
- `docs/roadmap/NNNN-title.md` — **one entry per file**. A roadmap entry is a unit of work: claimable,
  reviewable, completable alone. Two entries in one file is a defect, and a test says so. Every entry
  declares a `status:` field.
- `docs/diary/YYYY-MM-DD-NN.md` — the working log, and **where probe history lives**. No diary file
  exceeds 256 lines; at the ceiling, roll over. A diary is written, not read, and a test enforces the
  cap.
- `docs/WHITE-PAPER.md` — this file. It is **principles, not a log**: it changes when a principle
  changes, and never when a probe runs. Probe history belongs in the diary. A white paper that grows
  with every experiment stops being a document anyone reads, and the principles end up buried under
  history that only mattered on the day it was written. A test enforces that it stays short.

## 5. Commit discipline

- Commits are **atomic and buildable**. The message states **why**; the diff already says what.
- Never mix a refactor and a behaviour change in one commit.
- Slice by behaviour, not by file type. A commit should be reviewable in about fifteen minutes.
- Report residual risk and follow-ups explicitly. Silence reads as "nothing left", which is almost
  never true.

## 6. Terminal doctrine

- **Synchronised output (DEC 2026)** wraps every frame. Already proven in KittyCode; carried forward.
- **Capability detection must be active, not guessed.** Environment variables are a hint, never proof.
  Probe the terminal and cache the answer.
- **The reset ladder** is the recovery primitive, in order, cheapest first:
  1. **Selective cleanup** — leave alt screen, disable mouse and bracketed paste, `ESC[m`, show cursor.
  2. **DECSTR soft reset** (`CSI ! p`) — resets modes, cursor and attributes while **preserving screen
     contents and scrollback**. This is the primitive that was missing, and it is the correct middle
     tier.
  3. **RIS full reset** (`ESC c`) — destroys scrollback, visibly disruptive. Last resort only.
- The whole ladder is **testable against a PTY**, so it is written test-first, not by inspection.

## 7. Bans

- Unmeasured optimisation. Unprobed claims. Best-run reporting. Debug-build benchmarking.
- Sleeping or timing out inside a test. Tests that assert on nothing.
- Big-bang rewrites. Drive-by churn beyond the task's scope.
- Adding a dependency for convenience. **A dependency is an architectural decision.**
- Taking on a bug the task did not ask about, mid-task: report it as follow-up instead.

---
