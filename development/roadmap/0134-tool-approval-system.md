---
status: not-started
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
