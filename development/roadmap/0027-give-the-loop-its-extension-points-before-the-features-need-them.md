---
status: done
blocked-by: []
date: 2026-10-19
decision: ADR-0019
---

# 0027 — Give the loop its extension points before the features that need them

Other coding harnesses have approval prompts, hooks, MCP and dynamic tools, sub-agents, skills, prompt
templates, steering messages, compaction and custom session records. `ask` will want most of them, and
roadmap 0019 (approval) and 0012 (codemode) already need two. The loop in `AgentLoop` was built for a
headless single run, and a few of its choices are cheap now and expensive once features sit on them.

## What is true today (read from the code, not probed)

- `AgentLoop.run` reports through a closure `(AgentEvent) -> Void`, runs tool calls one at a time, and has
  no point where something may veto, rewrite or observe a call before it runs.
- `ToolRegistry` is built once, at init, from an array; there is no add or remove, so tools that appear
  mid-session (MCP, codemode) have no path in.
- `ToolDefinition` is name, description, schema. It says nothing about whether a tool is read-only,
  safe to run concurrently, or needs approval, which parallel calls and sandboxing both need. Tools now
  conform to `ArgumentTool` and declare their input with `ToolProperty` (ADR-0023), so a metadata field has
  one place to go and one default to be given.
- `SessionPayload` is a closed enum. A feature that records its own state (a skill load, a hook result,
  a sub-agent's transcript) must change that enum.
- The prompt is a `String`; `AgentSettings` has no place for per-run additions such as skills or reminders.

## The work

For each item, state what the feature needs, probe whether the current shape can carry it by writing the
smallest real use (an approval gate; a fake MCP tool added mid-run; a custom session entry; two read-only
tools run concurrently), and either record that it can, or change the shape with an ADR. The point is to
decide the seams while they are cheap, not to build the features.

## Done when

Each of the five has a recorded verdict and, where refuted, a decision. No feature is implemented here.

## Progress (2026-10-19, ADR-0028)

Done: `AgentHook` lets code block, rewrite or transform each tool call, in order, with each rule broken once in a
test. Still owed: a registry that takes tools after start (extensions, MCP), tool annotations (read-only,
destructive) for approval and parallel calls, and a place in a session for an extension's own records.

## Done (2026-10-30, close-out pass)

The verdicts, read from the code: hooks are `AgentHook` (ADR-0028). Tools after start: yes, the registry is live and MCP servers add
tools when they connect (ADR-0099, 0143). Annotations for approval: MCP's `readOnlyHint` and `destructiveHint` decide whether a call asks
(0153 finding 4); built-in tools are classified by name in `ApprovalPolicy` (0134). Parallel calls: not wanted yet, no decision needed
until a feature asks. An extension's own records in a session: not needed, since ADR-0123 keeps extensions to hooks and tools come
through MCP.
