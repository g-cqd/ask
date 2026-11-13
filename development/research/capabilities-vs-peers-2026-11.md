# What other coding agents do that ask does not, and what is worth taking (2026-11)

2026-11-13. The owner asked for a study of Claude Code, Codex, Mistral Vibe, Spettro, opencode and pi: their capabilities, the ones ask
lacks, and proposals where one would change how ask is used, made to fit ask. Sources: each one's documentation index
(code.claude.com/docs/llms.txt, developers.openai.com/codex/llms.txt, opencode.ai/docs/llms.txt, docs.mistral.ai/llms.txt) and
README (github.com/Aploide/spettro, github.com/earendil-works/pi and its docs folder), read 2026-11-13; ask's side from its source
(tools, commands, `--help`). A capability is listed when its documentation describes it; not tried.

## What ask already has that the others also have

Providers and subscriptions (Anthropic, Codex, Copilot, Antigravity, keys, named connections), MCP client with OAuth, skills,
subagents (`agent`), threads, `/btw`, hooks at many points with `run.stop` continues, approvals and a sandbox with narrowing, sessions
(resume, fork, rewind tree, encryption, compression), compaction with light clearing, task and ideas boards, thinking levels,
`/goal`, `/loop`, session search, `#123` references, git status, pictures, notifications, `ask -p`.

## What ask lacks

| Capability | Who has it | What it is |
|---|---|---|
| **File checkpoints, undo** | Claude Code (checkpointing, `/rewind` code), opencode (snapshots, `/undo` `/redo`) | Each turn's file changes kept, so the code (not only the conversation) goes back |
| **Plan mode** | Claude Code, Spettro (`/plan`, `/approve`), opencode (`plan` agent), Codex | A read-only planning phase; the plan approved, then carried out |
| **Editor integration (ACP)** | Spettro (`--acp`), opencode (ACP), Vibe (ACP, IDE docs), Claude Code and Codex (own IDE extensions) | The agent run by an editor (Zed, JetBrains, VS Code through ACP) in its native agent panel |
| **Machine-readable runs** | pi (JSON event stream, RPC, SDK), Claude Code (`stream-json`, Agent SDK), Codex (`exec --json`, App Server, SDK), opencode (server, SDK), Vibe (programmatic mode, app server) | A run's events as JSON lines, or an RPC to drive it, for scripts, CI and other tools |
| **Web fetch and search** | Claude Code, Codex, opencode, Vibe, Spettro (tools) | The model reads a URL or searches the web, within the approvals |
| **LSP diagnostics after edits** | opencode (LSP), Claude Code (code intelligence plugins) | After an edit, the language server's errors go back to the model at once |
| **Formatters on write** | opencode (formatters) | The project's formatter runs on each file the agent writes |
| **Code review** | Claude Code (`/code-review`, ultrareview, GitHub review), Codex (code review) | A review of the working changes or a pull request, as a command |
| **Project init** | Claude Code and Spettro (`/init`) | The repository read, an `AGENTS.md` written or updated |
| **Custom commands / prompt templates** | Spettro (`.spettro/commands`), pi (prompt templates), Codex (custom prompts), opencode (commands) | A saved prompt with arguments, run as `/name` |
| **Worktree-parallel sessions** | Claude Code (worktrees, agent view), Codex (worktrees) | Several agents at once, each in its own git worktree |
| **Remote control** | Spettro (`/remote` HTTP/SSE, Telegram), Claude Code (Remote Control, mobile, channels), Codex (remote connections) | Drive or watch a running session from another device |
| **Session export and sharing** | pi (share, HTML), Claude Code (artifacts), opencode (share) | A session written out as a readable file or link |
| **Plugins / packages** | Claude Code (plugins, marketplaces, mods), pi (packages, extensions), Vibe (plugins), opencode (plugins) | Skills, hooks, commands and MCP servers bundled and installed as one |
| **Advisor / fast model** | Claude Code (advisor tool, fast mode) | Work on a fast model, ask a stronger one at hard decisions |
| **Interactive terminal tool** | Spettro (PTY sessions for REPLs, debuggers, ssh) | The agent drives a program that needs a terminal |
| **Containers** | pi (containerization), Claude Code (devcontainers) | The agent runs inside a container |
| **Self-update** | Spettro (`/update`), pi (`pi update`), Claude Code | Updates itself from releases |

## Proposals

Ranked by lever on daily work over cost; each said as it would fit ask's principles (red-first, budgets, approvals, no hidden state).

1. **File checkpoints with `/rewind`.** ask's `/rewind` already picks a point in the conversation; it would also offer to restore the
   files the tools changed after it. Each `write`, `edit` and (when it can tell) `bash` change keeps the file's previous content in the
   session's store (sealed for encrypted sessions, as pictures are), recorded with the entry. Lever: high (safety of every edit). Cost:
   medium. Not a replacement for git: files outside the project and untracked ones too.
2. **Machine-readable runs: `ask -p --json`, then `ask serve` (RPC).** The loop's `AgentEvent`s as JSON lines (the type exists), for
   scripts, CI and other front ends; then a JSON-RPC mode on stdio for a long-lived driver. Lever: high (CI, editors, automation).
   Cost: low for JSON lines, medium for RPC.
3. **ACP for editors.** Built on (2): `ask --acp` speaks the Agent Client Protocol on stdio, so Zed and the JetBrains IDEs run ask in
   their agent panel, with ask's approvals as the editor's permission prompts. Lever: high for editor users. Cost: medium.
4. **Plan mode.** A mode (Shift+Tab, `/plan`) in which the sandbox is read-only and the model ends with a plan as a task list (the
   board exists); `/approve` turns it into the run. Cohesive with narrowing (0161) and the task board. Lever: medium-high. Cost: low.
5. **Diagnostics after edits.** After `edit`/`write`, the project's checker (an LSP server when configured, else a command such as
   `swift build`) runs and its new errors go back with the tool result, bounded. The check hook (0192) already runs a command at
   `run.stop`; this is the same at the edit. Lever: high for correctness. Cost: medium (LSP), low (command).
6. **Web fetch** (and search through a configured provider): a `fetch` tool returning a page as Markdown (AemiHTML exists), under the
   approvals, the text marked as untrusted (the prompt-injection policy of the engineering plan, D2). Lever: medium-high. Cost: low.
7. **`/review`.** A built-in skill: the working diff, or `#123`'s pull request through the forge, reviewed with a fixed rubric, the
   findings as tasks. Lever: medium. Cost: low.
8. **Custom commands.** `.ask/commands/NAME.md` with `$ARGUMENTS`, shown in the `/` picker. Skills cover much of it; a command is a
   skill the person runs by name without the model choosing it. Lever: medium. Cost: low.
9. **`/init`.** Reads the repository and writes or updates `AGENTS.md` (ask already reads it). Lever: low-medium. Cost: low.
10. **Session export.** `/export` to Markdown (and HTML with AemiHTML's writer), secrets redacted. Lever: medium. Cost: low.
11. **Worktree threads.** A thread or subagent may run in its own git worktree (`/thread --worktree`), merged back as a diff. Lever:
    medium-high for parallel work. Cost: medium.
12. **Advisor.** The reverse of the goal judge: a `consult` tool that asks a stronger model of the connection at a hard decision.
    Lever: medium (cost control). Cost: low.

Not proposed: telemetry, a marketplace (roadmap 0140's dylib platform covers extension), image generation, voice, mobile apps,
Telegram relays (a remote control can come after 0115's session takeover).

## Decisions for the owner

Which proposals to put on the roadmap, and in what order relative to the engineering plan.
