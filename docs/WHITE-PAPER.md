# ask — Project White Paper

The rules this project runs on. **Paste this at the start of every iteration.** An iteration that
cannot satisfy a rule below stops and fixes the rule, or asks to change it in writing — it does not
quietly proceed.

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
4. **Record the verdict** in the probe ledger below — claim, probe, result.
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
  and action-to-action delay. Each is a number with units, recorded in the probe ledger once measured.
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
| `-warn-long-function-bodies=100` | — | Fails the build on a body that runs long. |
| `-warn-long-expression-type-checking=500` | — | Fails the build on an accidental quadratic type-check. |

**Banned:** `-Ounchecked`. It strips the bounds and overflow checks `StrictMemorySafety` depends on,
trading correctness for a benchmark number.

## 4. Documentation law

- `docs/adr/NNNN-title.md` — **one decision per file**, stating context, decision, and consequences.
  A decision changed by new evidence is a **new ADR** that supersedes the old one; ADRs are not edited
  into an unrecognisable shape.
- `docs/roadmap/NNNN-title.md` — **one entry per file**. A roadmap entry is a unit of work: claimable,
  reviewable, completable alone. Two entries in one file is a defect, and a test says so. Every entry
  declares a `status:` field.
- `docs/diary/YYYY-MM-DD-NN.md` — the working log, and the probe ledger. **No diary file exceeds 256
  lines**; at the ceiling, roll over to the next file. A diary is written, not read, and a test enforces
  the cap.
- `docs/WHITE-PAPER.md` — this file.

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

## Probe ledger

Every entry: the claim, the probe, and the verdict. **This table only ever grows with probes that
actually ran.**

| # | Claim | Probe | Verdict |
|---|---|---|---|
| 1 | The five strict upcoming-feature flags are real and available in Swift 6.4 | `apple-docs search_docs source=swift-evolution` for each flag name | **CONFIRMED.** SE-0458 (6.2), SE-0409 (6.0), SE-0444 (6.1), SE-0470 (6.2), SE-0335. |
| 2 | `RegionBasedIsolation`, `DisableOutwardActorInference`, `InferSendableFromCaptures`, `DeprecateApplicationMain` are extra strictness to add | `swift build` with each added under `.v6` | **REFUTED.** Compiler: "already enabled as of the Swift 6 language mode". Removed from the table; `.v6` is what enables them. |
| 3 | An upcoming-feature flag breaks the test-target module handshake | Removed one flag at a time from the full set | **REFUTED.** The build failed identically with `v6` **alone**. The flags were never implicated. |
| 4 | `public` declarations cannot use `URL` under these settings | Full error text from `swift build` | **CONFIRMED, and the cause is SE-0409.** `InternalImportsByDefault` makes a plain `import Foundation` grant *internal* visibility, so `URL` was internal. Fixed with `public import Foundation`. |
| 5 | `FoundationEssentials` is the module declaring `URL` on this SDK | `swift build` after adding the import | **REFUTED.** `unable to resolve module dependency: 'FoundationEssentials'`. Corrected to `public import`. |
| 6 | `@testable import` is incompatible with the strict settings | Build the same test target in `release` and in `debug` | **PARTLY REFUTED.** The cause is not strictness: SwiftPM passes `-enable-testing` **only for debug builds**, so `@testable` cannot resolve in `release`. Policy: no `@testable`; test the public API in the shipping configuration. ADR-0002. |
| 7 | Aemi publishes versions `ask` can depend on | `git tag` in the Aemi clone | **REFUTED.** Zero tags. Aemi cannot be depended on by version; it must be tagged first. Dependency deferred. |
| 8 | The diary line-budget guard might be vacuous — a test that has only ever passed proves nothing | Wrote a 300-line diary file, ran the suite, removed it | **REFUTED.** The guard fired and named the offending file. It is load-bearing. |
| 9 | The one-entry-per-roadmap-file guard might be vacuous | Wrote a roadmap file holding two `## ` entries, ran the suite, removed it | **REFUTED.** The guard fired and named the file. It is load-bearing. |
| 10 | Something in `ask` requires a macOS floor above 15 | Built and ran the full suite at floors 15, 26 and 27 | **REFUTED.** All three pass with 0 errors. The floor is a free choice today, not a constraint. Floor set to 26. ADR-0003. |

**Open questions — claims not yet probed, and therefore not acted on:**

- Whether `-warn-long-function-bodies=100` is too aggressive for real source files.
- The measured value of each of the four performance budgets. **No number here is a guess; none has
  been measured yet.**
- Whether the DECSTR tier is supported by every terminal `ask` will meet.