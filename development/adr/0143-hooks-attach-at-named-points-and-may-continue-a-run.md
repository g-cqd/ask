---
status: accepted
date: 2026-11-02
---

# 0143 — Hooks attach at named points, each with the answers it may give, and may continue a run within limits

Extends ADR-0025's two tool points; roadmap 0192 is the design in full, with the owner's answers of 2026-11-02.

## Context

Extensions bring tools and hooks (roadmap 0140, 0033). The owner asked that where hooks attach be designed before either is built: at
ask's start, before and after a turn, after an answer that does not go on, and whether a hook may start another turn. `AgentHook` had
only `toolCall` and `toolResult`.

## Decision

- **The points**, each with what it may answer: `session.start` (context), `prompt.submit` (allow, block, rewrite, context),
  `request.before` (observe, rewrite the request), `response.after`, `tool.call` (allow, block, rewrite), `approval` (approve, refuse,
  ask), `tool.result` (rewrite, context), `run.stop` (stop, continue), `compaction.before` (instructions) and `compaction.after`,
  `settings.change`, `subagent.stop`, `waiting`, and `session.end`. There is no hook on every streamed event.
- **`run.stop` may continue a run.** Its message is recorded as a user entry labelled `[hook name]`, so a resume replays it. It is asked
  only once the person's follow-ups are in. It is told how many times hooks continued the run already. At most `hooks.maxContinues`
  continues a run (default 3), and each counts against the turn limit. At either limit the hooks are not asked, and the run says which
  limit ended it. Several continues at once join into one entry and count once.
- **`approval` answers in the person's place**, both ways, and never widens the sandbox.
- **Rewriting a request** changes that one request; the session keeps the conversation and records the rewrite.
- **Common rules**: hooks run in a fixed order (user's, then the project's); the first block wins, rewrites chain. Each declares a
  deadline and whether it fails open or closed. Points with no hook cost one check of an empty list.
- **Claude Code's hooks** are read as they are written, behind `hooks.claudeCode` (off by default), with its events mapped onto these
  points.
- `AgentHook` gains one method per point, each with a default that changes nothing, and a `name`.

## Consequences

- `run.stop` is built first (`AgentLoop.continuesByHook`, `AgentSettings.maximumHookContinues`); the other points follow it, each with
  tests for its answers.
- Hooks can make a run longer than the person asked for; the limits, the labelled entries and the notices keep that visible and bounded.
- 0033's draft messages `hooks/tool_call` and `hooks/tool_result` become `hooks/tool.call` and `hooks/tool.result`.
