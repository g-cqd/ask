---
status: accepted
date: 2026-10-25
---

# 0112 — A question asked while a lane is shown leads the status line

## Context

Roadmap 0062 step 3: a question must never wait unseen. With a focused lane (ADR-0110) the transcript is the runner's output and main's conversation, where the question is
written, is hidden. The answer keys already take precedence over everything (roadmap 0019), so the user could answer, but could not read the question.

## Decision

- While a lane is shown and a question waits, the status line **begins with the question and the answer keys** (`… y once · a for this session · n no ·`), then the usual
  line with the route. It leads so a narrow terminal clips the rest, not the question. The lane stays: answering needs no change of view, and `y`, `a`, `n` and Esc
  (no) work exactly as before. The question is also in main's transcript, as before, and is there when the user returns.
- Without a lane nothing changes.
- A runner that is itself waiting is a row in the strip, `waiting for approval`, and counts in the status (ADR-0105). Nothing in ask produces such a runner until subagents
  (0063): jobs never ask. The row's wording is tested with a runner built by hand; a question from a real child is **not** verified, and the name of the lane that asked
  is not yet in the question.

## Consequences

The visibility rule holds for the only questions that exist (main's). When children ask, their question text must name the lane; that is part of 0063.
