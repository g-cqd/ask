---
status: accepted
date: 2026-11-05
---

# 0146 — Subagents are threads the model starts, with only their task

Settles roadmap 0063's rules on 0195's threads (ADR-0144's groundwork, the owner's note n19), with the owner's answers of 2026-11-05.
Narrows within ADR-0032 (configuration narrows, never widens), ADR-0054 and ADR-0055 (authority never widens).

## Context

0063 proposed subagents as in-process loops with their own context, off by default, and left open what a child sees, which
definitions ask reads, whether a cheap model may resolve names it cannot match, and where a child's files live. 0195 then built
threads: forks run beside the conversation, merging back by a summary, with their own lanes, approvals and limits. The owner asked
that subagents be built on them, differing in what they inherit and who starts them.

## Decision

1. **Off means absent.** `agents.enabled`, false by default and read from the person's own configuration only (a project's may turn
   it off, never on). Off, no request carries an `agent` tool, no picker offers an agent, nothing on screen names one.
2. **A subagent is a thread the parent's model starts** with the `agent` tool. It is listed, laned, stopped, asked and merged as a
   thread is (0195); it always merges on its own; its summary is the `agent` call's result, labelled as a subagent's output and data
   to the parent, never instruction.
3. **It sees only its task** (the owner's answer). The tool takes three required fields, `task` (what to do), `context` (what it
   needs to know: paths, findings, constraints, decisions already made) and `done` (what completion is and what to return), so that the
   task is complete enough to finish without the parent's conversation (the owner's note). The child starts a conversation of its
   own with them and nothing else.
4. **Authority never widens.** The parent's sandbox or narrower; read-only tools unless `agents.allowWrites`; a definition's `tools`
   only narrows. Approvals are the thread's (0195) and follow `threads.questions`.
5. **Bounded.** `agents.maxDepth` 1 (a subagent cannot start one), at most `threads.max` at work with the threads, a turn limit per
   child (`agents.maxTurns`, 30). Stopping a parent stops its children, as a thread's subtree.
6. **Definitions.** ask's own, Markdown with frontmatter in `~/.config/ask/agents` and the workspace's `.agents/agents`, named by
   the tool's optional `agent` field. Other harnesses' definitions (Claude, Copilot, opencode, Antigravity in Markdown; Codex and Vibe
   in TOML) only when `agents.otherHarnesses` is on (the owner: behind a setting), off by default, read by the permissive reader
   skills use: `tools` only narrows, `model` is a preference resolved on the active connection, the parent's model the fallback.
7. **Names ask cannot match** in a definition (a model or a tool) are classified by a very cheap model on the active connection, on
   by default (the owner's answer; `agents.resolveWithModel`): tokens and ids only, checked against ask's own lists, cached, lazy,
   never at startup, and it can only narrow.
8. **Files stay with the session that ran them**, linked by id (the owner's answer): a fork or a compaction keeps the call's result
   that names the child, and the child's lane opens the original file.
9. `agents.model` may name a cheaper model; unset, the parent's. Another provider only when that connection is configured and
   `agents.allowOtherProviders` is on (off by default).

## Phases, each test first

1. `agents.enabled` (user-only), the `agent` tool with its three fields, a child thread with only its task and read-only tools,
   its summary as the labelled result. Depth 1.
2. Limits and stopping: `agents.maxTurns`, the shared count with `threads.max`, stop propagation probed with real processes.
3. ask's own definitions; then other harnesses' behind `agents.otherHarnesses`.
4. Model-assisted resolution, on by default.
5. Resume: a resumed parent shows its children's lanes from their files, with no running state.

## Consequences

Off costs nothing: no tool definition, no request, no row. On, a child costs what a thread costs (measured in 0195: 0.16 MiB beyond
the first thread) plus its own requests; it never sees the parent's conversation, so its first request is small. The parent's model
must write a task that stands alone; the three required fields make it say what a fork would have told the child.
