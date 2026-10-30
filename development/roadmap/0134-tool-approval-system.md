---
status: done
blocked-by: []
date: 2026-10-29
---

# 0134 — An approval system for tool calls

Owner wish (2026-10-29 00:00): an approval system, on by default, that asks yes or no (with the confirmation picker of 0116) before each
tool call such as bash, or any tool that would reach another network address than the model provider's. It is bypassed by command-line
flags or by configuration. Both configuration settings take lists to always allow, or always require approval for, per ask tool. A further
setting widens or narrows what the person can change from inside a running ask: everything, or only some kinds (both with confirmation
and selector pickers).

## Still owed

- Relate it to what exists: the sandbox approval (ADR-0021 ff.) and the destructive-MCP-tool approval (ADR-0111) already ask in their own
  ways; this is one system over them, not a third.
- Settings, typed (0118): `approvals.default` (`"ask"`, `"allow"`), `approvals.allow` and `approvals.ask` as lists of tool names (and
  patterns for MCP tools), `approvals.scope` (`"anything"`, `"narrowing-only"`, `"none"`); the flags `--yes` / `--ask-always` or similar.
- Network: the model provider's own host is the one allowed address; any other connection needs a decision (0021 is the enforcement side).
- What "default on" costs in daily use: a first run asks for every bash call. Decide with the owner whether read-only tools are exempt.
- Depends on 0116 (the picker as a confirmation step).

## Owner's decision (2026-10-29)

Read-only tools are exempt from approval by default. A configuration setting can make them require approval too (a per-tool or per-kind
`ask` list already covers it; the default list is what changes).

## Ready to build; questions for the owner (2026-10-29)

The confirmation section (0116) and the MCP rule (0153 finding 4) are done, so this is next. What is settled: on by default; read-only
tools exempt by default; a config list can make them ask; the answers are Allow this time · Allow for the session · Deny. Open:

1. **What "Allow for the session" covers for `bash`:** every later command (simple, but one "a" opens everything), or the same command
   word (`swift …`, `git status` but not `git push`?), or only the identical command line. Proposed: the same program and first word
   (`git status`, `swift build`), so `rm` or `git push` still ask.
2. **Which built-in tools count as read-only:** proposed `read`, file listing and search, `mcp_search`, job output; asking: `bash`,
   `write`, `edit`, job input. Should `write` and `edit` ask, given the sandbox already keeps them in the workspace? Proposed: they ask
   too, with "Allow for the session" covering further edits of the same file.
3. **`ask -p`, with no one to answer:** today it runs what the sandbox allows. With approvals on, every bash call would be refused unless
   allowed. Proposed: `-p` keeps today's behaviour (the command line is the consent), and `--ask` is an error with `-p`.
4. **Flags:** `--yes` (allow everything for this run) and `--ask-always` (ask even what the config allows). Names to confirm.
5. **Settings** (person's own file only, like `credentials`): `approvals.default` (`"ask"` | `"allow"`), `approvals.allow` and
   `approvals.ask` (tool names, `mcp__server__*` patterns), `approvals.scope` (`"anything"`, `"narrowing-only"`, `"none"`: what an
   "Always" answer may write back to the config from inside ask; until then no answer writes config).

## Owner's answers (2026-10-29), and done (ADR-0134)

1. Another answer for commands: allow the program for the session. 2 to 5: as proposed.

Built: `ApprovalPolicy`, `CommandWords`, `CallGrants`, `ToolCallGate` in `AskAgentCore/Approvals`; the `approvals` section; `--yes`,
`--ask-always`; the four-answer command question. Tests: `CommandWordsTests`, `ApprovalPolicyTests`, `CallGrantsTests`,
`ToolCallGateTests`, `ApprovalsConfigurationTests`, `CommandApprovalTests`; a mutation that runs a denied call turns the gate test red.
Through the release binary: `probe-interactive.py` section X (git status asks with both session answers, `git status --short` then runs
unasked, `git log` asks, a program grant covers `git diff`, `ls` denied and the model told), 272 checks in all; `probe-mcp-screen.py` 12;
ten other screen probes pass with `--yes`.

Not done: an "Always allow (saved to your config)" answer, which `approvals.scope` is for; 0153's protected paths behind this question.

