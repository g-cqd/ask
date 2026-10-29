---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0146 — Claude Code's tools, as ideas for ask's features

Owner request (2026-10-29): record every tool name the installed Claude Code offers, so that ask can study which features it lacks.
This entry inventories features and compares them with ask; implementation and tool mappings are assessed separately.

## Source and its limits

`strings` over `/opt/homebrew/Caskroom/claude-code@latest/2.1.312/claude` (a 276 MB compiled executable with its JavaScript inside),
then a search for string arrays that name `Bash`, `Read`, `Edit`, `Glob` or `Grep`, and for single names. Nothing was disassembled or
run. **Confirmed** means the name sits in one of those tool arrays. **Present** means the string is in the binary, and the name is likely
a tool but its role was not checked; `Config`, `Brief` and `Sleep` in particular may be unrelated strings. Descriptions below are
inferred from the names, not read from the binary.

## Confirmed in the tool arrays (26)

| Claude Code | Likely role | ask today |
| --- | --- | --- |
| `Bash` | run a command | `bash` |
| `Read`, `NotebookRead` | read a file, a notebook | `read` (text and images); no notebook reading |
| `Write`, `Edit`, `MultiEdit` | write, replace, several replacements at once | `write`, `edit`; one replacement a call |
| `NotebookEdit` | edit a Jupyter cell | none |
| `Glob`, `Grep` | find files by pattern, search contents | through `bash` (0043 owes search tools) |
| `WebFetch`, `WebSearch` | fetch a page, search the web | none |
| `Task`, `Agent` | start a subagent | none (0063, off by default) |
| `TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskGet`, `TaskList`, `TaskStop` | a task list the model keeps | none; `job`/`job_stop` are processes, not plans |
| `Skill` | load a skill | `skill` |
| `AskUserQuestion` | ask the person questions | none (0117) |
| `ToolSearch` | find deferred tools | `mcp_search`/`mcp_call`, MCP only |
| `SendUserMessage` | a message to the person outside the reply | none |
| `REPL`, `JavaScript` | evaluate code | none (codemode 0012 is shelved) |
| `Cd` | change the working directory | none; the workspace is fixed |

## Present in the binary (28)

`ExitPlanMode`, `EnterPlanMode` (a planning mode), `BashOutput`, `KillShell`, `KillBash`, `TaskOutput` (background commands; ask has
`job`, `wait`, `job_stop`), `ListMcpResourcesTool`, `ReadMcpResourceTool` (MCP resources; 0123), `LSP` (language-server queries),
`EnterWorktree`, `ExitWorktree` (git worktrees), `Monitor`, `CronCreate`, `CronDelete`, `CronList`, `ScheduleWakeup`, `RemoteTrigger`
(scheduled and remote runs), `LS`, `SendMessage`, `TeamCreate`, `TeamDelete` (agents talking to agents), `Sleep`, `PushNotification`,
`Config`, `Brief`, `StructuredOutput`, `WebBrowser`, `Workflow`. Display names also seen: `PowerShell`, `SendFile`, `ListAgents`,
`Artifact`, `MCP Wait For Servers`.

## Candidates for ask, to assess one by one

1. **Search tools** (`Glob`, `Grep`): already owed by 0043; fewer `bash` calls, sandbox-checked paths, typed results.
2. **Several replacements in one edit** (`MultiEdit`): fewer turns for a refactor.
3. **A task list the model keeps** (`TodoWrite`, `Task*`): shown below the input like the job rows (0062).
4. **Questions to the person** (`AskUserQuestion`): 0117.
5. **Web fetch and search**: through the sandbox's network levels (0021), or an MCP server instead.
6. **Plan mode** (`EnterPlanMode`, `ExitPlanMode`): a read-only phase that ends with an approval (0116, 0134).
7. **Language-server queries** (`LSP`): definitions and references; Xcode's MCP server covers part of it for Swift.
8. **Worktrees** (`EnterWorktree`): isolated changes, close to fork (0115) and the sandbox.
9. **MCP resources** (`ListMcpResourcesTool`, `ReadMcpResourceTool`): with 0123.
10. **Scheduling and notifications** (`Cron*`, `ScheduleWakeup`, `PushNotification`): lowest priority.

Each candidate gets its own entry when it is taken up, with ask's budgets and sandbox rules applied.
