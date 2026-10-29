---
status: not-started
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
