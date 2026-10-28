---
name: probe-before-adopting
description: Run a probe before acting on any claim in the ask ecosystem, and record the verdict in the diary. Use when adopting a belief about a toolchain, a protocol, a library's behaviour, a platform guarantee, a performance number, or someone else's code, and whenever a measurement is quoted, a diagnosis is proposed, or a "known" behaviour is about to be relied on. Not for recording principles in the white paper, which changes when a principle changes rather than when a probe runs.
---

# Probe before adopting

Every claim in this ecosystem is named, given a probe that could fail, run, and recorded — before it
is acted on. The diary in this repository is unusually valuable precisely because it preserves the
failures: claims that looked solid and were wrong.

Use this when you are about to *act* on something you believe. If you are merely recording a principle,
you want `documentation-law` instead.

## The protocol

1. **Name the claim.** Write it as a sentence that could be true or false. "SwiftPM passes
   `-enable-testing` only for debug builds" could be false. "`@testable` is incompatible with strict
   concurrency" could be false. Vague claims cannot be probed.
2. **Design a probe that would make it false if it is false.** This is the step that gets skipped.
   Ask: what result would prove me wrong? If no result could, redesign the probe.
3. **Run it.** Record the command verbatim.
4. **Record the verdict in the diary** — claim, probe, result. Append to the table in the most recent
   `development/diary/YYYY-MM-DD-NN.md`.
5. **Act only then.** An unprobed claim is an open question, never a fact.

Read `references/probe-patterns.md` for the shapes of probe that have worked here, and for the
counterfactuals worth running when a probe comes back green.

## What is not a probe

- Confidence, experience, or "it is well known that…"
- A blog post, or a second model's opinion
- Documentation read out of context, without the specific section that answers the question
- A passing build that does not distinguish between the hypotheses
- Inference from a different configuration than the one shipping — a debug build, a different toolchain,
  a different machine

## The failure mode to watch for

The bisect lesson, from this repo's own history: a flag was blamed for a build failure it had nothing to
do with. It was cleared by removing it — from a build that *still failed*, because four other flags were
still present. The claim was false and nearly became a written constraint in the white paper.

**A probe that cannot fail is not a probe.** When a removal or change leaves the symptom intact, that is
a result — it eliminates a hypothesis. When a change makes the symptom vanish, ask whether anything
*else* changed at the same time before concluding anything.

## Green results need a counterfactual

A probe that confirms a suspicion is weaker evidence than it looks. Before trusting a green result on a
fix, ask what the same probe reported *before* the fix. The diary's own tests were probed by deliberately
breaking them: a 300-line diary file made the line-budget test fail and name the file; a roadmap file
holding two entries made the granularity test fail and name the file. Both removed, both returned to
green. That is what makes those guards load-bearing rather than decorative.

For a new guard, budget one deliberate break before you trust it.

## Verdicts

Use one of three words, and mean them:

- **CONFIRMED** — the probe could have failed and did not.
- **REFUTED** — the probe failed the belief. The belief loses; record the contradiction and move on.
  Do not re-litigate a settled decision unless new evidence contradicts it.
- **INCONCLUSIVE** — the probe could not distinguish the hypotheses. Say so plainly rather than
  reporting a number that means nothing. An inconclusive result is a real result.

## What counts as a performance claim

Before/after numbers, same harness, same inputs, same build configuration, with units. Report median
and spread, never the best run. Interleave the runs so background load cancels out of the ratio. A
performance claim without those numbers is not a claim this project will act on.