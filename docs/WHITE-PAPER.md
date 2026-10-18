# ask — Project White Paper

The rules this project runs on. **Paste this at the start of every iteration.** An iteration that
cannot satisfy a rule below stops and fixes the rule, or asks to change it in writing — it does not
quietly proceed.

## Runtime principles

These are what "fast" is allowed to mean here. They bind every target in the ecosystem, and each one
excludes something that would otherwise look like an optimisation.

**A lightweight runtime.** A binary links only what it uses. No umbrella target that re-exports
everything, no speculative generality, no framework pulled in for one function. Startup cost is paid
once per process, so what a binary **links** is paid for at every launch — a statement about link
**weight**, not module **count**, which was measured at 0.067 ms between one target and twenty and is
inside noise. Fine-grained targets are free; the discipline is on what is linked. Cold start is 6.23 ms
of a 25 ms budget, so the headroom is 18.77 ms and granularity does not rest on the measurement. ADR-0009
records the correction.

**Fewest allocations.** Allocation is not free and it is not only slow — it fragments, and a fragmented
allocator costs more in cache misses than the work that needed it. The hot path allocates zero times,
and a buffer is reused rather than re-made. Where a budget can be stated it is **measured and enforced
by a test**, because an allocation ceiling nobody checks is a wish.

**Close to zero copy.** Work in `ContiguousArray` and `UnsafeMutableRawBufferPointer` from the boundary
inward. No `Array`/`ContiguousArray` bridging, no `String` round-trip per keystroke, no copying a
buffer to append to it. Copy once, at the edge where data enters or leaves the process. Copy-on-write
is what a runtime reaches for when it cannot avoid a copy; here the aim is to have nothing to copy.

**Safest, and still near zero-copy.** Requirements together, never a trade against each other. No
`-Ounchecked`, no disabled bounds or overflow checks, no `unsafe` not justified in a comment. Being
both fast and safe means **doing less work** — diff a frame instead of repainting it, reuse a buffer
instead of allocating one — not removing the checks that catch the bugs.

**Modern primitives, and a written reason for every escape.** The floor is macOS 26, so `Mutex`, `Atomic`,
`InlineArray`, `Span` and `RawSpan` all compile — `NSLock`, `os_unfair_lock`, `pthread_mutex` and
`DispatchQueue` are banned. Shared mutable state goes in a `Mutex` or an `Atomic`; an actor is for a real
async boundary or an invariant that must hold across an `await`, and is the last resort.
`@concurrent` and `nonisolated` are the default answer. `@unchecked Sendable` is permitted only with the
invariant written next to it.

**Tests are deterministic.** No `Task.yield`, no `Task.sleep`, no polling, no wall-clock assertion. Wait
on the event — Aemi's `AsyncEventProbe` under a `TestClock`, or a `CheckedContinuation` the code under
test resumes. A test that depends on scheduling can pass for the wrong reason.

Both are enforced by `SourceStandards`, and each rule was probed by breaking it with a violation that
compiles.

**Every claim is measured.** A performance claim without before-and-after numbers, same harness, same
configuration, with units, is not a claim this project will act on.

**Generic tools belong in Aemi.** A tool not specific to one application is promoted to Aemi, the kernel
package, and specialised packages build on it. This binds the whole ecosystem, not only `ask`. The test is
whether a second consumer is plausible, not whether one exists today. Promotion is a real change to a
shared package, so it is measured, reviewed and pinned by dependents like any other.

**Reliable by default, and never silent.** Damage costs only what is actually damaged: everything intact
still loads, every repair is reported, and reading never writes. Refusing input needs a written safety
reason, because convenience and reliability are requirements together, like speed and safety. Other agents
are studied by running their code, never from their source alone; notes live in `docs/research/`.

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

**Not a probe:** confidence, experience, or "it is well known that…"; a blog post, a second model, or
documentation read out of context; a passing build that does not distinguish between the hypotheses;
inference from a *different* configuration than the one shipping.

**The bisect lesson.** A flag blamed for a failure was cleared by removing it — from a build that still
failed, because four other flags were present. The claim was false and nearly became a written
constraint. *A probe that cannot fail is not a probe.*

**Escalation.** When a probe contradicts a confident belief, the belief loses; record the contradiction
in the diary. Do not re-litigate a settled decision unless new evidence contradicts it.

---

## 1. Red TDD

- **Red first.** Written, run, and observed to fail **for the right reason**, before the implementation
  exists. A test that has never failed has proven nothing.
- **One behaviour per test**, named in backticks as a sentence:
  ``@Test func `every diary file is within the line budget`()`` — the name says what must hold, so a
  failure names its own cause.
- **Green by the minimum *general* code** — not code special-cased to the test's input.
- **Refactor with tests green**, one named move at a time.
- **Red and green land in the same commit**, so history stays buildable and `git bisect` keeps working.
- **Never** assert on nothing, never share mutable state between tests, never test a private method to
  test itself.
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

Prefer behavior tests through public APIs; where internal access is justified, enable testability
explicitly for optimized tests. Shipping binaries and benchmarks are built separately, without it, and
are not claimed identical. Compiler settings require controlled probes, not blanket prohibitions
inferred from a failed build.

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

The terminal belongs to **TerminalKit**, and so does its doctrine — synchronised output, capability
detection, and the tiered reset ladder. Not restated here: a copy is a second thing to drift. Two
corrections stay, because they are the shape of the mistake rather than the detail. This section once
asserted DECSTR resets modes while preserving scrollback; TerminalKit measured four emulators and
**DECSTR resets no DEC private mode** (TerminalKit ADR-0002). And it once read capabilities from
environment variables, until an inherited `KITTY_WINDOW_ID` made Terminal.app claim a protocol it does
not speak — so capabilities are **probed**, and silence means *unknown*, not *unsupported*.

Probing is not free: two queries against a terminal that answers nothing cost **520 ms** against a 25 ms
budget, so a probe never gates the first frame.

## 7. Bans

- Unmeasured optimisation. Unprobed claims. Best-run reporting. Debug-build benchmarking.
- Sleeping or timing out inside a test. Tests that assert on nothing.
- Big-bang rewrites. Drive-by churn beyond the task's scope.
- Adding a dependency for convenience. **A dependency is an architectural decision.**
- Taking on a bug the task did not ask about, mid-task: report it as follow-up instead.

---
