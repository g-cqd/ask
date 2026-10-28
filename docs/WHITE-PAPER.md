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
inside noise. Fine-grained targets are free; the discipline is on what is linked (ADR-0009).

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

Both are enforced by `SourceStandards`, each rule probed by breaking it with a violation that compiles.

**Every change that can affect performance is benchmarked.** Not only optimisations: a dependency, a data
structure, an extra system call, a different encoder. Before and after, same harness, same release build,
median and spread with units, in the diary and the commit message. A change whose cost is unknown is not
finished, and a performance claim without those numbers is not one this project acts on. Small wins count,
a hoisted allocation or a `Span` for an array compounds on every keystroke; one that moves no number is reverted.

**Generic tools belong in Aemi.** A tool not specific to one application is promoted to Aemi, the kernel
package, and specialised packages build on it; this binds the whole ecosystem. The test is whether a second
consumer is plausible, not whether one exists. Promotion is a real change to a shared package: measured,
reviewed and pinned by dependents like any other.

**System APIs before subprocesses.** Where macOS has an API, ask calls its current form (`apple-docs`), not a
tool: `NSPasteboard`, not `pbcopy` (ADR-0127); a power assertion, not `caffeinate`. A subprocess stays only where
it is the point (model commands, MCP servers, the self-check), where no API exists (`sandbox-exec`) or where the
tool is the authority (`git ls-files`), saying why beside it. Roadmap 0101 keeps the inventory.

**Reliable by default, and never silent.** Damage costs only what is actually damaged: everything intact
still loads, every repair is reported, reading never writes. Refusing input needs a written safety reason,
because convenience and reliability are requirements together, like speed and safety. Other agents are
studied by running their code, never from their source alone; notes live in `docs/research/`.

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
2. **Design the probe** that would make it false if it is false; one that cannot fail proves nothing.
3. **Run it.** Record the command verbatim.
4. **Record the verdict** in the diary: claim, probe, result.
5. **Act only then.** An unprobed claim is written down as an open question, never as a fact.

**Not a probe:** confidence, experience, or "it is well known that…"; a blog post, a second model, or
documentation read out of context; a passing build that does not distinguish between the hypotheses;
inference from a *different* configuration than the one shipping.

**The bisect lesson.** A flag blamed for a failure was "cleared" from a build that still failed for four
other flags; the false claim nearly became a constraint. *A probe that cannot fail is not a probe.*

**Escalation.** A probe that contradicts a confident belief wins, and the diary records it. A settled
decision is reopened only by new evidence.

---

## 1. Red TDD

- **Red first.** Written, run, and observed to fail **for the right reason**, before the implementation
  exists. A test that has never failed has proven nothing.
- **One behaviour per test**, named in backticks as a sentence:
  ``@Test func `every diary file is within the line budget`()`` — the name says what must hold, so a
  failure names its own cause.
- **Green by the minimum *general* code** — not code special-cased to the test's input.
- **Refactor with tests green**, one named move at a time. **Red and green land in the same commit**, so
  history stays buildable and `git bisect` keeps working.
- **Never** share mutable state between tests or test a private method for itself. Coverage is measured by
  **behaviour**, never by percentage.

## 2. Performance doctrine

- **Measure to find the bottleneck, and measure again to prove the fix.**
- **Release only.** `swift build` and `swift test` run `-c release`. A debug build measures a program
  nobody ships. See ADR-0002.
- **Percentiles, not averages.** Users feel p95 and p99.
- **Budgets, stated as numbers:** cold start, idle memory, input delay and action-to-action delay, each with
  units and recorded in the diary once measured. An unmeasured budget is not a budget.
- **Order of attack:** don't do the work → do less work → do it elsewhere → do it in parallel →
  micro-optimise. The order says where to look first, not what to skip (ADR-0016).
- **A benchmark is the evidence.** It runs the shipping build's code path, not a model of it in
  another language, and lands with the change it measures.
- **Never trade correctness or safety for speed.** No `-Ounchecked` in this project, ever.

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

Prefer behaviour tests through public APIs; where internal access is justified, optimized tests enable
testability explicitly, and shipping binaries and benchmarks are built without it. Compiler settings
require controlled probes, not prohibitions inferred from a failed build.

## 4. Documentation law

- `docs/adr/NNNN-title.md` — **one decision per file**: context, decision, consequences. New evidence makes a
  **new ADR that supersedes** the old one; records are never edited into an unrecognisable shape.
- `docs/roadmap/NNNN-title.md` — **one entry per file**. A roadmap entry is a unit of work: claimable,
  reviewable, completable alone. Two entries in one file is a defect, and a test says so. Every entry
  declares a `status:` field.
- `docs/diary/YYYY-MM-DD-NN.md` — the working log, and **where probe history lives**. No diary file
  exceeds 256 lines; at the ceiling, roll over. A diary is written, not read, and a test enforces the
  cap.
- `docs/WHITE-PAPER.md` — this file: **principles, not a log**. It changes when a principle changes, never
  when a probe runs (that belongs in the diary), and a test keeps it short enough to be read.

## 5. Commit discipline

- Commits are **atomic and buildable**. The message states **why**; the diff already says what.
- Never mix a refactor and a behaviour change in one commit.
- Slice by behaviour, not by file type. A commit should be reviewable in about fifteen minutes.
- Report residual risk and follow-ups explicitly: silence reads as "nothing left", which is rarely true.

## 6. Terminal doctrine

The terminal belongs to **TerminalKit**, and so does its doctrine (synchronised output, capability detection,
the tiered reset ladder); a copy here would be a second thing to drift. Two corrections stay as the shape of
the mistake: **DECSTR resets no DEC private mode** (measured on four emulators, TerminalKit ADR-0002), and
capabilities are **probed**, never read from environment variables (an inherited `KITTY_WINDOW_ID` once lied);
silence means *unknown*, not *unsupported*. Probing is not free: two queries against a terminal that answers
nothing cost **520 ms** against a 25 ms budget, so a probe never gates the first frame.

## 7. Bans

- Unbenchmarked performance-affecting changes. Unprobed claims. Best-run or debug-build benchmarking.
  Sleeping or timing out inside a test. Tests that assert on nothing.
- Big-bang rewrites. Drive-by churn beyond the task's scope. Adding a dependency for convenience:
  **a dependency is an architectural decision.**
- Taking on a bug the task did not ask about, mid-task: report it as follow-up instead.

## 8. Structure and idiom

- **The file listing is the map.** One top-level type per file, named for it; no file past 250 lines; provider
  names only in provider code; code only tests use does not ship (ADR-0021). Tests enforce each of them.
- **Ask what Swift already offers before hand-rolling.** When a refactor or factorisation is on the table,
  look at the language first: result builders, scoped closures (`object { }`, `with…`), `callAsFunction`,
  key paths, protocol extensions with default implementations, typed throws over `Result` switches,
  property wrappers, macros. Compile the candidates, pin behaviour with a characterisation test, benchmark
  on a request path, and record what was rejected.
- **A finding is a question.** deadwood, dolly and arcleak (pinned by version and hash) end in one of three
  answers: fix it, name the abstraction the duplicate was missing, or accept it at the source with a
  written reason. A baseline is for legacy debt, never for new code.

---
