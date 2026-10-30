---
status: not-started
blocked-by: ["0061"]
date: 2026-10-24
---

# 0063 — Subagents, off by default

Ranked after skills (0061) and the runner tree (0062) by the owner. **Off means absent**: with `agents.enabled` false (the default) the model has
no `agent` tool and so cannot try, the picker offers no agent, and the screen shows no agent rows; `/agents` says it is off and how to turn it on.
`agents.enabled` is **user-level only**: a project's configuration may turn it off and never on (ADR-0032's "narrow, never widen"). Design and
questions: `development/research/skills-and-agents-design-2026-10.md`.

## Proposed rules, each needing an ADR before code

1. A child is an **in-process agent loop** with its own context and a short task from the parent; its result returns to the parent as an
   **ordinary tool result**, so the parent's session keeps its shape and resumes unchanged.
2. A child's transcript is **its own file** (the owner's answer), `sessions/<parent>/agents/<id>.jsonl`, linked by id; the closed `SessionPayload` does not change.
3. **Authority never widens** (ADR-0054, ADR-0055): the parent's sandbox or narrower, a **read-only tool set by default** (`agents.allowWrites`
   to change it), approvals to the user through the lane (0062).
4. **Bounded:** `agents.maxDepth` default **1** (a subagent cannot start one; raising it is what makes the tree deeper), `agents.maxConcurrent`,
   a turn limit and a token limit per child; cancelling the parent or the lane stops the child and its descendants.
5. A child's output is **data to the parent, labelled by origin**, never instruction.
6. `agents.model` may name a cheaper model for children; unset means the parent's. A child's model never moves to another provider
   unless that connection is configured and `agents.allowOtherProviders` is on (off by default).

## Named agents from other harnesses

The owner's machine holds 14 agent definitions in each of six harness formats (Markdown with frontmatter for Claude, Copilot, opencode and
Antigravity, TOML for Codex and Vibe). If ask loads another harness's agent definitions at all, they come through the same **permissive reader**
as skills (roadmap 0061): `tools` is a restriction that can never add a tool, `model` is a preference resolved on the active connection with the
parent's model as the fallback, `maxTurns` and `steps` and `effort` or `reasoningEffort` map onto ask's own limits and thinking level where they
match and are kept as notes where they do not. That ask loads them at all is still undecided.

## Model-assisted resolution

The owner asked that, when a model or tool token cannot be matched deterministically, a **very cheap model on the active connection** classify it against
ask's own list. The bounds (tokens and ids only, validated against ask's list, cached, lazy, never on the startup path, can only narrow) are in the
design note; whether it is on by default is still open.

## Not decided

Where child sessions live when the parent is forked or compacted; what a child may see of the parent's context (nothing but its task is the safe
default); named agent definitions (`.agents/agents/*.md`) versus only the anonymous tool; and addressing a session that is not a child
(0048's transport), which this does not need and does not settle.

## Rules that must hold, each with a failing test first

- Disabled: the request has no `agent` tool; the picker, the strip and the sidebar show no agent; a project file cannot enable it.
- A child never has a tool or a sandbox right its parent lacks; a write tool is refused in a read-only child.
- A subagent cannot start a subagent at depth 1, and can at depth 2 up to the limit; the tree shows it.
- Cancelling a lane stops its child and every descendant, with no work left running (probed with real processes).
- A child's approval question reaches the user whatever lane has focus, and is answerable from main.
- A resumed parent shows its earlier children's lanes with their recorded transcripts and no running state.
- A child's result in the parent is marked as a subagent's output.

## Probes

Real children against a fake provider: the lane appears, focus shows the child's transcript, a message to the focused lane steers it, and
cancel stops it; then once against a real model with the owner present, since every claim about cost and behaviour is otherwise a claim about a fake.

## Done when

The ADRs exist, the rules have tests that failed first, the probes pass with the default off and on, and the cost of having the feature off is
zero requests, zero tool definitions and no measurable frame cost.
