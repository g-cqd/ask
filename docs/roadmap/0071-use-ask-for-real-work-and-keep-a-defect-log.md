---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0071 — Use ask for real work, and keep a defect log

Four hundred commits and 102 ADRs describe probes, and the repository records **no sustained use of ask on a real task**: the word "dogfood" appears in no file under
`docs/` (searched today), the diaries are probe ledgers, and the live runs of the last week were one tool call at a time. The project's own rule is that a belief is a claim until a probe
shows it; "ask is good enough to work with" is such a claim, and the only probe that can show it false is work.

## The work

1. **Do real work with `ask` itself**: take small, real roadmap items (a documentation fix, a test, a one-file change) and have `ask` do them in a scratch worktree, on each provider
   the owner has (Claude, Codex, Antigravity), at least five sessions of an hour or more. The author of an entry runs it; the owner's own daily use counts and is better.
2. **Keep a defect log** as a diary: for each friction, the exact steps, what was expected, what happened, and whether it was ask, the provider, or the person. No fix during the session.
3. **Sort it afterwards** into: a defect with a reproduction (a roadmap entry or a fix, test first), a missing feature (an entry, ranked), and a question (the open-questions table).
4. **Measure what a session costs**: tokens in and out per task, how often compaction ran, how many requests were refused or retried, wall time of the turns. These are the numbers
   the context and retry designs have never had.

## Done when

The diary holds at least five sessions, each defect has a reproduction or a question, and the sorted list exists with the ranking the owner agreed.

## Not claimed

That the defects will be in the areas the roadmap currently favours. The reason to do this is that nobody knows.
