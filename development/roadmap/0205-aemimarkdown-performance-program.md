---
status: not-started
blocked-by: []
date: 2026-11-04
---

# 0205 — AemiMarkdown: a performance program for the complete parse, the stream and the edit

The owner, 2026-11-04: whatever the file sizes, use every optimization technique to spend the least resources and parse the fastest, complete or incremental. A typical file is 3 KB (diary claim 13), so this is about the least CPU, memory and energy per document and the lowest latency per edit, not about big files.
The method is the white paper's: every technique is an experiment with a hypothesis, a probe that can fail, a before and after (median and spread, release, quiet machine) in its own commit, and a change that moves no number is reverted. Design: research note, section 13.

## Baselines (diary claim 14, to be re-measured on a quiet machine first)

About 100 MB/s on a corpus of real documents; 83% of the time in our own code, 16% in the SIMD set-scan kernel, 10% splitting table cells, 6.5% copy-on-write uniqueness checks, 5.7% memory moves, 10% in the Swift runtime; 0.47 bytes of tape per source byte; zero allocations once warm for a reused parser
(AemiMarkdown's README), a streamed delta at 1.6 µs p50. A harness fixes them first: the corpus (real documents, the spec examples, hostile inputs), throughput, allocations, resident bytes, tape bytes per source byte, the streamed-delta cost and the edit cost of 0203, as one command that writes a comparable record.

## Experiments, each its own commit (E1 to E14)

| # | Technique | Hypothesis, and what would make it fail |
|---|---|---|
| E1 | Take copy-on-write checks out of the hot arrays: unsafe buffers in arenas with the `unsafe` justified, noncopyable parser state | 5 to 6% of the time is uniqueness checks; fails if the checks move elsewhere |
| E2 | Table rows: a SIMD search for pipes and escapes in place of byte-at-a-time cell splitting | 10% of the time; table-heavy corpus gains, prose does not |
| E3 | Two-stage parse: classify 16 bytes at a time with nibble table lookups into bitmasks of special bytes, the inline parser walks set bits | the inline parser reads every byte; fails if building the masks costs more than the bytes skipped |
| E4 | Implicit text runs: the inline tape stores markup only, text is the gap | tape bytes per source byte falls, writes fall; fails if readers pay more to rebuild the gaps |
| E5 | Lazy inlines: parse a block's inlines when it is read, with a dependency stamp for references | the viewer and a preview read a screenful; fails if the stamp costs more than the parse it saves |
| E6 | Read the file by mapping it, parse from the mapped bytes, no copy (`RawSpan` over an owner) | resident memory of a preview drops by the file's size; fails if page faults cost more than a copy at these sizes |
| E7 | Bulk skipping: a fenced block's lines to the closing fence with no container open; SIMD indentation and blank-line counting | code-heavy documents; fails on prose |
| E8 | A speculative parallel parse above a size threshold: chunks from a clean top-level boundary, a chunk whose start did not match is parsed again; the inline phase in parallel per leaf | the same restart-and-resync primitive as 0203; fails below the size where thread hand-off costs more than the parse |
| E9 | The content hash fused with the scan, and the hash function chosen by measurement (XXH64 against XXH3 against a hardware CRC pair) | the hash is under 1% already; kept only if it moves the edit numbers |
| E10 | One flat open-addressing table for reference labels in place of a dictionary of byte arrays | an allocation per label today; also the multimap 0203 needs |
| E11 | Pack `BlockState.Open` (a large struct with a 128-bit alignment word) and the open stack | cache footprint per line; fails if the profile does not show it |
| E12 | `InlineArray` for small stacks, `Span` at the boundaries, no existentials, an `@inlinable` audit of cross-module calls | the runtime is 10% of the time |
| E13 | Streaming: the cost of the provisional tail at each snapshot and of the open leaf | already 1.6 µs p50; look for the tail |
| E14 | Profile-guided and link-time optimization **in app builds only** (Xcode build settings; library manifests may carry no unsafe flags) | decided by a probe of the gain against the build step |

## Red first, and the rule that keeps them honest

- The scalar implementation stays in the tests as the oracle of every SIMD kernel and every rewritten loop; kernels are checked on random and hostile input over guard pages (Aemi's guarded bytes), under the address sanitizer, and by the fuzz harness; the spec ratchet and the differential tests against cmark do not move.
- Allocation ceilings (`CAemiTestKitMalloc`) and a growth test keep the bounds; the no-recursion guarantee is checked by running deep nesting on a constrained stack (Aemi's test kit has the runner).
- A table of kept and reverted experiments in the diary: technique, before, after, spread, verdict.

## Done when

The baseline record and the final record are in the diary, every experiment has a verdict, the kept ones pass the gates (format, lint, release tests, deadwood, dolly, arcleak, mutation testing on the changed files), and the README's numbers are re-measured on the document corpus as well as on assistant messages.
Target, a hypothesis to test and not a promise: at least twice the throughput on documents, the tape at or under 0.3 bytes per source byte, no allocation in a warm complete parse, and an edit cost independent of the document's size.

## Not in scope

Anything that trades correctness or safety for speed: no `-Ounchecked`, no disabled bounds or overflow checks, no unjustified `unsafe`.

## Progress and rules (2026-11-04)

Baseline on the public corpus (998 documents, fetched by a setup step, never committed): 70 to 80 instructions per byte, 60 to 105 MB/s of CPU time, at about 3.4 instructions per cycle (diary 2026-11-04-02, claims 18 and 19). Every experiment is judged on instructions and CPU time (`AemiMetrics.ProcessProbe`), not wall-clock, because the machine is not quiet. Use `AemiInterner`, `AemiKernels` and `AemiTestKit` before writing a new one; a new kernel (table cells) is promoted to `AemiKernels` by an ADR in Aemi, with its exhaustive, fuzz and guard-page tests.

## Progress, first round (2026-11-04)

Kept: table cells by SIMD scan (E2), wyhash for block hashes and stamps (E9), no label normalization when the document has no definition and no case folding for text without case; reverted: the in-place read of open blocks and a local copy of the source in the cursor loop. On the public corpus -3 to -10% instructions per byte, and a flat profile afterwards (diary 2026-11-04-02, claim 23). Left: E1, E3 to E8, E10, E12 to E14, each structural; the scalar oracles are in the tests of each kept change.

