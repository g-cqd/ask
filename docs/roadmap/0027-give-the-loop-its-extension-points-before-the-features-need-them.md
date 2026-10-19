---
status: not-started
blocked-by: ["0026"]
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
