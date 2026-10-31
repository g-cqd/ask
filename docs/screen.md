# The screen and its keys

The conversation fills the screen, the input sits at the bottom, and a status line below it shows the model, what is running, and the
background jobs.

The status line starts with a spinner while ask works. It reads `Compacting...` in purple while the conversation is being summarised, and
`Reconnecting...` in yellow while ask waits to try again after the connection dropped; neither adds anything to the conversation.

## Writing a prompt

- **Enter** sends. **Shift+Enter** or **Ctrl+J** starts a new line; a paste keeps its line breaks.
- **`/`** at the start lists the commands, narrowed as you type. Up and Down choose; Enter or Tab inserts the choice without sending it, so
  a second Enter runs it. A click on a row runs it at once.
- **`@`** at the start of a word lists the project's files (`.gitignore` applies, and only what the sandbox lets ask read). Enter inserts `@path`;
  add `:12-30` for a line range. The model then reads the file itself.
- **`/continue`**, or just `continue`, `resume`, `go ahead` or `go` as the whole message, or **Right pressed twice** on an empty input while nothing
  runs, tells the model to carry on where it stopped. A sentence that merely starts with one of those words is sent as written.

While the model is working, **Enter** queues your message as steering: it is sent after the model's current step. `/follow-up TEXT` (or
**Alt+Enter**, where the terminal reports it) queues a message for when the turn is over.

## Stopping and leaving

| Key | What it does |
|---|---|
| **Esc** | Goes back one step: closes a list, clears a selection, leaves a job's output. With nothing left to close and a turn running, it stops the turn: press it twice within two seconds. |
| **Ctrl+C** | One step per press: copies a selection; otherwise erases the input; otherwise stops a running turn; otherwise asks "press Ctrl+C again to quit", and a second press within two seconds quits. |
| **Ctrl+D** | Quits when the input is empty and nothing is running. |
| `/quit` | Quits, stopping a running turn first. |

When you stop a turn, nothing is added to the conversation: what was still going (a command, the reasoning, a compaction) turns orange
and ends with `⊘`, apart from a failure's red `✗`, and whatever it had already returned is kept. The messages you queued are sent by default; `ui.queuedOnStop` changes that. `ui.interruptKeys` and the two
confirmation settings choose which keys stop a turn and how many presses it takes (see [Configuration](configuration.md#ui)).

## Editing

| Key | What it does |
|---|---|
| Up, Down | Move between lines of the input. From its first line, Up brings back what you sent before, commands included, and Down goes forward again to what you were typing. Once you change a message you brought back, Down goes no further. |
| Home, End, Ctrl+A, Ctrl+E | Start and end of the line. |
| Ctrl+U, Ctrl+K | Delete to the start or end of the line. |
| Ctrl+W, Option+Backspace | Delete the previous word. Option+Delete deletes the next one. |
| Ctrl+X | Cuts the selection, or clears the whole input when nothing is selected. |
| Command+C, X, V | Copy, cut and paste, as Ctrl+C, X and V do. |
| Shift+arrow, Home, End | Select from the keyboard. Typing replaces a selection. |

With the mouse, a click puts the cursor, a drag selects, a double click takes a word and a triple click a line. A selection in the
conversation copies what is shown, as soon as you let go.

## Reading the conversation

- File paths, web addresses and email addresses anywhere in the conversation are links: a click opens a file or folder in its app, a
  page in your browser, an address in Mail. A file that would run (an app, a script, a program) is shown in the Finder instead.
- Tool calls, the model's thinking and long code blocks start **folded** to one line. Click a block to open it in place; **Ctrl+O** opens or
  folds the tool output, **Ctrl+T** the thinking and **Ctrl+G** the code blocks.
- A shell block is headed by its limits, then the command: `shell · timeout 5 min · swift build`; a timeout equal to the default is not
  written (`ui.timeout`, `ui.timeoutLabel`). Folded, a long command is cut with `…`
  before the status; opened, the command is shown in full and brighter, with its output below.
- Scroll with the wheel or **Page Up**. The view stays on what you were reading while new text arrives, and the status line counts the lines
  below (`12 lines below`). Click that count, press **Page Down**, or **End** with an empty input, to return to the end.

## When the model asks you

The model can ask you up to four questions at once, each with choices and room for a note. They appear above the input, as a
command's approval does, with a tab per question when there are several. A choice is marked `( )` when you pick one, `[ ]` when you may
check several. The note is the row after the last choice.

- **Tab** and **Shift+Tab** move between the tabs, the choices and the note.
- On the choices, **Up** and **Down** highlight one, and **Space** or its number selects it.
- On the tabs, **Left** and **Right** change question.
- On the note, you type as in the input; nothing you type reaches the note unless it has the focus.
- **Enter** goes to the next question and, after the last, to a review of every answer, which Enter sends and Esc leaves.
- **Esc** on a question declines them all, and the model carries on with its own judgement.

A click picks a choice, focuses the note, or opens a tab. The input below keeps what you had typed. `ask -p` never offers the model
this tool.

## Background jobs

The model can run commands in the background. The status line counts them (`· 2 jobs`). Click the count, or type `/jobs`, to list them
below the input: Up and Down choose one, Enter shows its output in place of the conversation, and Esc goes back. On a wide screen,
`/sidebar` or **Ctrl+\\** shows the same list beside the conversation. Jobs never outlive ask.

## Commands

| Command | What it does |
|---|---|
| `/model` | Choose the model, from every account you are signed in to. `/model NAME` sets it directly; `/model reset` undoes it. |
| `/thinking` | Choose how much the model thinks, among the levels it accepts. |
| `/login`, `/logout` | Sign in to or out of an account without leaving. |
| `/new` | Start a new conversation; the old one stays saved. |
| `/resume` | Switch to another saved conversation. |
| `/rewind`, `/fork` | Go back to an earlier prompt, or continue in a copy. See [Sessions](sessions.md). |
| `/compact` | Summarise the conversation now to free room in the context window. |
| `/config` | Edit settings, or `/config show` to re-read the files and show them. |
| `/mcp` | Show the MCP servers and their tools. |
| `/skill:NAME` | Ask for a skill by name. |
| `/jobs`, `/sidebar` | Show the background jobs. |
| `/verbose` | Show or hide details: the sandbox in force, the files read. |
| `/help` | List the commands. |
| `/quit` | Leave. |

While the model works, commands still work:

- `/model`, `/thinking`, `/config` and `/mcp` at once: a new model, effort or setting applies from the very next request, even in the
  middle of a run of tool calls, and a retry waiting on a busy model goes to the new one at once.
- `/login` and `/logout` at once; signing out of the account the turn uses waits for the turn to end.
- `/fork` at once: the copy holds what the turn has written so far, and you stay with the turn; `/resume` switches to the copy.
- `/compact`, `/new`, `/resume`, `/rewind` and `/reload` wait for the turn to end, shown as waiting, then run in the order you typed
  them. If you stop the turn, they follow `ui.queuedOnStop` like queued messages: with `none` they come back to the input.
- `/skill:NAME` is a message, so it joins the turn like any other.
