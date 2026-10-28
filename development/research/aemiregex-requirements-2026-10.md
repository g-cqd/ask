# A regex kernel and `AemiRegex`: what would have to exist (2026-10-24)

Written at the owner's request after a Swift `Regex` measurement. Evidence is labelled **observed** (a probe ran here, archived in
`development/research/probes/`), **read** (source or documentation read, nothing run) or **open** (not probed). Nothing here is built. Diary
2026-10-24-39 holds the probe ledger.

## 1. What was asked, and what the evidence says about each part

| Ask | Finding |
|---|---|
| A Sendable, safe wrapper over `NSRegularExpression` | **Observed:** `NSRegularExpression` already compiles as `Sendable` under Swift 6.4 language mode, so Sendability is not the gap. The gap is **safety** (below) and ergonomics (UTF-16 `NSRange` against `String.Index`). |
| Remove the Swift `Regex` overload | **Observed:** Swift `Regex` took 173 ms per search of 642 files against 29 ms for `NSRegularExpression` (diary 2026-10-24-30). In `ask` it appears in **one runtime place** (`ProviderFailure+Overflow.swift`: three short patterns on a refusal message, an error path) and **two test helpers**. The libswift_StringProcessing dylib is linked implicitly and Aemi's own JSON schema code uses `Regex`, so removing our uses would not remove the dylib (**read**). |
| A NEON assembly kernel to compile and match regexes | See 2: no part of the evidence calls for assembly. |
| Port it to x86_64 | **Observed:** the same Swift `SIMD16<UInt8>` source lowers to `cmeq.16b` + `umaxv` on arm64 and `pcmpeqb` + `pmovmskb` on x86_64. There is nothing to port. AVX2 (`vpcmpeqb`) appears only with an explicit target flag. **Observed:** the same probe built for x86_64 and run under Rosetta gives the same counts as arm64 (176 regex matches, 23,923 SIMD candidates, 23,929 `memchr` candidates). That is evidence of equal results, not of speed: Rosetta's timings (SIMD 0.68 ms, `memchr` 0.58 ms) say nothing about native Intel or AMD. |
| Call it `AemiRegex` | It then belongs in the Aemi repository, not in `ask` (AGENTS.md: a generic tool is promoted when a second consumer is plausible). |

## 2. Why the kernel is not assembly

The question is how much of a search is matching. Over the same 665 Swift files (2.16 MB), warm and in memory:

| Step | Median |
|---|---|
| `NSRegularExpression` `func\s+\w+\(.*async`, every file | 15.75 ms |
| Swift `SIMD16<UInt8>` scan for the first byte `f` (23,923 candidates) | 0.75 ms |
| libc `memchr` loop for the same byte (23,929; NEON inside libc) | 0.45 ms |
| Reading and enumerating all files (earlier probe) | 13.7 ms |

Three consequences, all from one machine at load about 11, so the ratios hold better than the absolute numbers:

1. A prefilter in plain Swift SIMD is within 0.3 ms of libc's hand-tuned `memchr` on 2 MB. Assembly would have to beat 0.75 ms.
2. The prefilter rejects 99% of positions (23.9k candidates in 2.16M bytes), so a regex engine behind it works on 1% of the input.
3. The floor of any in-process search is reading the files (13.7 ms). A perfect kernel saves at most about 15 ms per search, against a model
   call that takes seconds. ADR-0081 already decided not to build in-process search tools for this reason.

**Revisit assembly only if** a Swift kernel is measured and loses to the best available native code by a factor that matters on a
real workload (suggested bar: more than 2x on at least 100 MB, on both architectures). A regex engine's bottleneck is usually the
automaton's table walk, which is serial and not a SIMD problem at all; SIMD earns its keep in literal prefilters (memchr, multi-literal "Teddy"
style), which Swift SIMD already expresses. Assembly would also add a C or assembly target to a package that today has neither, a
second thing to audit under `StrictMemorySafety`, and a per-architecture maintenance load. **Open:** multi-literal prefilter speed, AVX2
against SSE2, and Swift SIMD against `memchr` on inputs where matches are dense.

## 3. What `NSRegularExpression` is unsafe for, and how far a guard goes

The risk Aemi's `SchemaPattern` names (**read**: its doc comment says it avoids `NSRegularExpression` to rule out catastrophic backtracking
from attacker-supplied patterns) is real:

- **Observed:** `^(a+)+$` on `aaa…ab` takes 11.9 ms at 18 characters, 215 ms at 22, 1.0 s at 24 and 3.8 s at 26: it quadruples every two
  characters.
- **Observed:** `enumerateMatches(options: [.reportProgress])` calls the block with the `.progress` flag and lets it stop the match. A cap
  of 50 calls ended that same pattern in 11 to 14 ms at lengths 20, 26, 40 and 200. The call count is deterministic (838 on both runs of
  length 22), so a budget can be a count, not a clock.
- **Observed:** on a benign 4 MB scan the block fires about once per input position (3,999,997 calls, 76 ms), so a budget has to scale with the
  input (for example a base plus a multiple of the length). The ratio between "normal" and "catastrophic" calls per position was not
  measured and decides whether a length-scaled budget separates them. **Open.**

A guard bounds time. It does not give linear-time matching, and it turns a pattern that is merely slow into an error. Which of those is
wanted is a decision (section 6).

## 4. What `AemiRegex` would be

A regex engine whose matching time is linear in the input for every pattern, which is the only way "safe" can be a property rather than
a budget. This is the design of RE2 and Rust's `regex` crate; **read, not run**, so every claim about them below is a claim to probe.

**Needed, in order of dependency:**

1. **A syntax decision** (owner). The practical subset: literals, `.`, classes and ranges, `\d \w \s \b`, anchors, groups (capturing and
   not), alternation, `* + ? {m,n}` and their lazy forms. Excluded by construction, as in RE2: backreferences and lookaround, which cannot
   run in linear time. Everything `ask` uses today (3 patterns, 2 test helpers) is inside that subset.
2. **A parser to an AST, and a compiler to an NFA.** Pattern size and nesting limits, and an error type that names the position.
3. **A matcher without backtracking.** A Pike VM gives captures in time proportional to pattern times input; a lazy DFA gives faster
   match or no-match without captures, with a **bounded state cache** (a memory cap is part of the safety story, not a tuning knob).
4. **Text model.** Matching on UTF-8 bytes, results as `Range<String.Index>` / `Substring`. Whether `\w` and `\d` follow Unicode (as ICU and
   Swift `Regex` do) or ASCII is a decision with a cost: a Unicode `\w` is a large table.
5. **The prefilter kernel** of section 2: extract required literals from the pattern, scan for them with SIMD, and start the matcher
   only at candidates. Scalar fallback for the tail and for targets without SIMD.
6. **A `Sendable` value type** (compiled once, matched from any task), typed throws, no global mutable state; the DFA cache either per
   call or behind a lock, a decision with a cost under contention.

**The verification it needs, because the project's rule is that a test which never failed proves nothing:**

- **An independent oracle.** Differential testing against `NSRegularExpression` on generated patterns and inputs inside the shared
  subset. Known differences have to be listed rather than discovered: Unicode classes, case folding, `$` before a final newline, `\b`, leftmost-first
  against leftmost-longest alternation.
- A pathological corpus (nested quantifiers, huge alternations, long inputs) with a stated time ceiling per case.
- Property tests (matching is deterministic, a match's captures lie inside it, adding an unrelated branch never removes a match).
- Mutation against a proven-green baseline, as for every rule in this repository.
- Byte-exact tests on both architectures. x86_64 runs under Rosetta for correctness (observed above); native Intel or AMD timing needs a host. **Open.**

**Placement.** The Aemi repository pins and layers its own targets (a kernel tier and a test kit); a new target there needs that
repository's own rules, read first, and a pin bump in `ask`'s `Package.swift` and `Package.resolved`, which must agree. Nothing was changed
there and nothing in it was read beyond how `ask` pins it.

## 5. A smaller path that does not wait for any of that

**Stage 0 (in `ask`, small):** a local wrapper over `NSRegularExpression` with typed errors, a `String.Index` result type, and the progress
guard above, replacing the three runtime patterns and two test helpers. It removes the Swift `Regex` uses, adds the safety bound, and does
not preclude `AemiRegex` later, because the wrapper's API is the API `AemiRegex` would have to meet. Its cost (ICU load on first use,
which only the refusal path pays) was **not measured**; neither was whether removing the literals changes binary size.

**Stage 1 (Aemi):** the prefilter kernel alone, Swift SIMD, with the measurements of section 2 repeated on x86_64.

**Stage 2 (Aemi):** the engine of section 4, behind the oracle.

Each stage ends with a probe that can fail: stage 0, the three real refusal messages and the two helpers give identical results to today's;
stage 1, the prefilter's candidates are a superset of every true match on the corpus; stage 2, zero differences from the oracle on a stated
number of generated cases, and no case over the time ceiling.

## 6. What the owner has to decide

1. **Home:** Aemi (so `AemiRegex`), or `ask` until a second consumer exists.
2. **Safety meaning:** "bounded and reported" (stage 0 is enough) or "linear time by construction" (stage 2).
3. **Syntax and Unicode scope** (section 4, items 1 and 4).
4. **Whether `ask` needs any of this now.** Today's `Regex` use is three short strings on an error path. The costs measured are real only for a
   search tool that ADR-0081 decided not to build. If the work is wanted as a library for other consumers, say so, because that is the justification
   the repository's rules ask for.
5. **Hosts:** an Intel or AMD machine for native x86_64 numbers, or acceptance of Rosetta for correctness only.
