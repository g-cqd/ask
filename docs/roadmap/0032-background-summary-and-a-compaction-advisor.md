---
status: not-started
blocked-by:
date: 2026-10-19
---

# 0032 — A summary kept up to date in the background, and an advisor for when to compact

The user's proposal, 2026-10-19. It is to be investigated, not built yet.

## The idea

- **Opt-in.** A command turns it on and installs what it needs, from a list of choices: a cheap hosted model
  or a local one.
- **Light compaction, kept up to date.** While the user works, a cheap or local model writes the summary
  and amends it after each turn. Compaction then has a summary ready instead of stopping the run for a
  summarisation request.
- **A decision model.** It judges, from the state of the conversation and the task in progress, when to
  propose compaction and what to do automatically. For example: compact at a natural break, not in the
  middle of a debugging thread; drop old tool output first.

## What is already known (probed 2026-10-19, diary 10)

- **Server-side context edits exist.** The models API lists `context_management` edits:
  - `clear_thinking_20251015`, which drops earlier thinking blocks; pi's behaviour points the same way;
  - `clear_tool_uses_20250919`;
  - `compact_20260112`, with a 150,000-token default trigger.

  The first two are the cheap tier of "light compaction": they shed bulk without summarising.
- **A cheap hosted model exists:** `claude-haiku-5-5` is in the model listing, with a 1,000,000-token window.
- **The seam exists.** 0030 records a compaction as plain text, `.compaction(summary:firstKept:)`, and a
  summary kept up to date elsewhere can fill that same entry. Sending the summary as plain text answered as
  well as Anthropic's signed compaction block did.

## To investigate

- **What dropping thinking and tool output saves,** and what it costs the answers: replay real sessions with
  and without these edits, then compare token counts and outcomes.
- **Local models on macOS 26.** Probe for each: context size, speed, summary quality on real transcripts,
  and memory. Candidates include Apple's on-device Foundation Models and a llama.cpp or MLX model.
  - Budget: the background summariser must not break ask's idle-memory and input-delay budgets. Running it
    out of process probably decides that.
- **Incremental summary quality.** Amending a summary turn by turn can drift or lose detail. Compare against
  a one-shot summary of the same transcript, using questions about early details as the test.
- **What the advisor can see:**
  - token counts;
  - turn boundaries;
  - whether tools are mid-sequence;
  - a task state that does not exist yet.
- **What the advisor costs.** Its own requests must cost less than the compactions it saves.
- **Trust.** The summariser reads the whole conversation. A hosted cheap model sends it to a provider. The
  choice must be explicit, follow ADR-0020's capability rules, and be off by default.

## Done when

This entry becomes a design note with measured numbers, and a decision on whether to build it.
