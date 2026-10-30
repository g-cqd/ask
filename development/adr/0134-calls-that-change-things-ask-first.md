---
status: accepted
date: 2026-10-29
---

# 0134 — Calls that change things ask first

## Context

Roadmap 0134: the owner asked for approval before tool calls, on by default, bypassable by flags and configuration, with lists per tool.
The sandbox (ADR-0021 ff.) already asks about calls that reach beyond it, and MCP tools ask unless their server says they are read-only
(0153). The confirmation section (0116) gives one way to answer.

## Decision

1. **What asks:** `bash`, `write`, `edit`, and `job` with action `input`. Every other built-in tool is read-only or harmless (`read`,
   `mcp_search`, `wait`, `skill`, `narrow_sandbox`, job status and stopping) and runs unasked. MCP tools keep their own rule.
2. **The answers:** Allow this time; Allow for the session, which remembers the call's subcommands (`git status`) for a command, the
   file for a write or edit, the tool otherwise; for a command, also Allow the program (`git`) for the session; Deny. A line is covered
   only when every command it runs is, never when it holds a substitution (`$(…)`, a backquote).
3. **`approvals` in the person's own file** (a project's is refused): `default` (`ask` | `allow`), `allow` and `ask` lists of tool
   names or `prefix*` patterns (`ask` wins; `mcp_call` is judged as `mcp__server__tool`), `scope` (kept for a future "always" answer;
   no answer writes the file).
4. **Flags:** `--yes` allows every call for the run, `--ask-always` asks even what the configuration allows; both are carried into a
   `/reload`. Neither touches the sandbox's own questions.
5. **`ask -p` asks nothing:** running it is the consent, so its loop has no gate.
6. **Mechanism:** `ToolContext.callGate` (policy plus answerer), consulted by `ToolRegistry.run` before the tool; the conversation keeps
   the session's grants (`CallGrants`).

## Consequences

- A first interactive session asks before each new command, file and job input; "Allow `git` for the session" is one answer for a
  whole program.
- The screen probes launch with `--yes` when the binary has it, so a probe about something else is not stopped by a question; the
  probes about approvals (interactive X, the MCP part of `probe-mcp-screen`) do not.
- A call that asks both questions (beyond the sandbox, and changing things) asks the approval first, then the sandbox.
