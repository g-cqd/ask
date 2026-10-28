# Research note — how six terminal coding agents draw their screen and take input, October 2026

How opencode, Pi, Claude Code, Codex, Vibe and Antigravity (`agy`) handle commands, references, skills, agents, disclosure and the
mouse, from what each shows when started and given a `/`, and from each vendor's documentation, on 2026-10-20. Decisions belong in
ADRs; this note is the evidence roadmap 0015, 0048 and 0051 cite.

## Method, and what it cannot tell you

- **Observed:** each installed harness was run in a pty (opencode 2.0.32, Claude Code 2.1.301, Codex 0.163.0, Vibe 2.26.1,
  Antigravity 1.4.2, Pi 1.3.0's own build) in a throwaway workspace. Only the start screen, a trust prompt, and the `/` menu were
  opened. **No prompt was sent to any of them**, so none of their transcripts, tool output, diffs or subagent views was seen.
- **Docs:** claims marked *(docs)* come from the vendor's documentation, fetched or read locally, and are not confirmed by running.
- **Not checked at all:** whether any of the six selects text, copies on select, folds output with a click, or draws images. This
  note says nothing about their behaviour there.

## Commands, references, skills, agents (observed unless marked)

| Harness | `/` menu | `@` | Agents and sessions |
|---|---|---|---|
| Claude Code | commands and skills together, two-line descriptions | mentions *(docs)* | a panel under the prompt for forks and subagents; opening one sends your messages to it *(docs)* |
| Codex | `/agents` ("open the agent command center") | file search *(docs)* | `/subagents` switches the active thread *(docs)*; skills by `$` or `/skills` *(docs)* |
| opencode | `/debug /diff /editor /effort /models /thinking /variants` | files and subagents *(docs)* | Tab switches primary agents; child sessions by leader keys *(docs)* |
| Pi | commands with a `(1/50)` counter; skills as `/skill:name` *(docs)* | file search *(docs)* | no built-in subagents *(docs)* |
| Vibe | commands and 29 skills, long descriptions wrapped | not observed | `--agent` at launch |
| Antigravity | `/agents`, and a skill (`/review-agent`) in the same list; "tab Complete" | not observed | custom agents listed by `/agents` |

Skills in the `/` list is the common choice (three of six observed, a fourth documented). Every harness that lets you reach a
running agent does it by **switching into** it. None was found that lets you **address** one without switching, which is the idea
in roadmap 0048, and the search was not exhaustive.

## Disclosure and folding

| Harness | What is documented or observed |
|---|---|
| Pi | `Ctrl+O` expands or collapses tool output and `Ctrl+T` shows or hides thinking blocks *(docs)*. In its source a hidden block shows the label "Thinking...", and a block can override the global setting: `thinkingVisibilityOverrides.get(runIndex) ?? hideThinkingBlock`. So visibility is **per block, with a default**, which is the model roadmap 0051 proposes |
| opencode | `/thinking` toggles the visibility of thinking blocks, and says it does not change whether the model reasons *(docs)* |
| Antigravity | observed at start: "Verbosity now defaults to medium ... tool calls and thoughts roll up into summaries", adjustable in `/config > Verbosity`. The fold is a **level**, not a per-block toggle |
| Claude Code | `Ctrl+T` toggles a task list; `/tasks` lists background shells and subagents; `Ctrl+B` backgrounds a command *(docs)* |
| Codex | the background-agent panel can be expanded to inspect status, stop agents or open a thread *(docs)* |

## The mouse *(docs)*

| Harness | What the documentation says |
|---|---|
| Claude Code | in its diff panel, "click its row in the list" to jump to a file, and scroll the panel with the wheel |
| opencode | `tui.json` has `mouse` (`true` in the documented example; the default is not stated in what was read) and `scroll_speed`, so the mouse is a **setting** |
| Pi | "Terminal support for mouse input, keyboard shortcuts, and inline images varies", and it offers a fullscreen mode (the editor and status stay fixed while the transcript scrolls inside the window) and a regular mode that uses the terminal's own scrollback |

The pattern in the documentation is that the mouse is an option, clicks are on lists and panels rather than on transcript blocks,
and the terminal's own scrollback is the alternative to an app-drawn scroll. How any of them handles selection while reporting the
mouse is **not documented in what was read**.

## Input

Pi: `Shift+Enter` adds a line, `Ctrl+G` opens an external editor, `Alt+Enter` queues a follow-up, `Alt+Up` returns queued messages
to the editor *(docs)*. opencode has an `/editor` command (observed). Claude Code documents `Ctrl+Enter` to send queued messages.
None of this was tested against a bounded input that scrolls.

## What this suggests for ask, and what it does not

- Disclosure as a **per-block state with a global default and a command** (Pi's shape) fits the owner's wish to fold one thing
  without folding everything, and to click it. A **level** (Antigravity's shape) is the alternative for a summary view.
- The mouse as an **opt-out setting** matches opencode and Pi, and is what gives the terminal's own selection back (roadmap 0051).
- Nothing here shows how to make a selection survive a scroll or copy on release. That is new in the kit (TerminalKit roadmap
  0017), and the six were not tested for it.
