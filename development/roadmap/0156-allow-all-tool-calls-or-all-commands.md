---
status: done
blocked-by: []
date: 2026-10-30
---

# 0156 — Allow all tool calls, or all commands, from the configuration and the command line

Owner wish (2026-10-30): an "allow all tool calls" option and/or an "allow all commands" one, combined or separate, and the ask
arguments to set them at startup.

## Done (2026-10-30)

One list, so 0154 can settle the names once: `approvals.allow` takes, besides tool names and `prefix*` patterns, `"commands"` (every
command) and `"all"` (every tool call, MCP tools' own questions included); `--allow NAME`, repeatable, adds to it for one run
(`ask --allow commands`, `ask --allow all`, `ask --allow write`) and is carried into `/reload`. `--yes` stays, the same as `--allow all`.
`approvals.ask` still wins over both; `--allow` with `--ask-always` is refused. Tests: `ApprovalAllowWordsTests`; interactive probe
section X2 (`--allow commands`: two commands run unasked, a write asks, allowed it is written); the whole interactive probe passes, 282
checks.

