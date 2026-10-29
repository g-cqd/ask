---
status: done
blocked-by: []
date: 2026-10-29
---

# 0145 — Summarise MCP startup in one block

Owner wish (2026-10-29 14:57): replace one connection block per MCP server, including tool-search advice, with a combined summary such as
"4 MCP servers connected." and, when applicable, "N failed to connect."

Keep individual server details and tool exposure/search explanations in `/mcp` and verbose output. Startup connects asynchronously, so
update one status rather than adding one block per callback; do not declare success while connections are pending. Failures must remain
visible and actionable, without exposing credentials. Tests should cover mixed success/failure, disabled servers, zero servers, delayed
completion and reload without duplicated blocks. Coordinate with lazy connection work (0143).

Filed while prioritising Claude investigation 0144; no implementation in this change. Wishes file is intentionally untouched.

## Done (2026-10-29)

Startup says one block, once every enabled server has connected or failed (`MCPStartupSummary`): `4 MCP servers connected.`, or
`1 MCP server connected. 1 failed to connect:` with a line per failure and its reason; `No MCP server connected. …` when none did. Nothing
with no server or only disabled ones, and nothing while one is still connecting (the summary waits for the slowest; stopping before then
says nothing). A configuration change that replaces the servers says the new set's summary once. Per-server lines are gone from startup;
`/mcp` keeps each server's state and now carries the hint for a searched server (`name the ones you want in mcp.<name>.tools`); `ask -p`
still prints problems and remarks to stderr. A server going away later is still said on its own. Tests: `MCPStartupSummaryTests` (mixed,
all failed, disabled, none, pending; a mutation counting a connecting server as settled turns it red), the host, hub and search tests
updated; `probe-mcp-screen.py` through the release binary. Verbose output does not add per-server lines (not built; `/mcp` covers it).

