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
**Alt+Enter**, where the terminal reports it) queues a message for when the turn is over. **Option+Up**, with an empty input, takes the newest
queued message back into the input to edit, as long as the model has not taken it yet; Enter queues it again, last.

## Stopping and leaving

| Key | What it does |
|---|---|
| **Esc** | Goes back one step: closes a list, clears a selection, leaves a job's output. With nothing left to close and a turn running, it stops the turn: press it twice within two seconds. |
| **Ctrl+C** | One step per press: copies a selection; otherwise erases the input; otherwise stops a running turn; otherwise asks "press Ctrl+C again to quit", and a second press within two seconds quits. |
| **Ctrl+D** | Quits when the input is empty and nothing is running. |
| `/quit` | Quits, stopping a running turn first. |

When you stop a turn, nothing is added to the conversation: what was still going (a command, the reasoning, a compaction) turns orange
and ends with `⊘`, apart from a failure's red `✗`, and whatever it had already returned is kept. The messages you queued are sent by default; `ui.queuedOnStop` changes that. `ui.stopKeys` and `ui.stopTwice` choose which keys stop a turn and how many presses it takes (see [Configuration](configuration.md#ui)).

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
- Tool blocks are headed by their modifiers first, then their target: `read · lines 10–45 · path`, `write · 2 B · path`, `write · exact replacement · path`, `job · stop · #abcd`, and for commands `shell · timeout 5 min · swift build`; a timeout equal to the default is not
  written (`ui.showTimeout`, `ui.timeoutLabel`). Folded, a long command is cut with `…`
  before the status; opened, the command is shown in full and brighter, with its output below.
- A command's own colours show in its output: the colours, bold, dim, italic, underline and strikethrough it asks for, and the links
  it writes (OSC 8) to web pages, files and email addresses. Everything else a program writes to steer a terminal is removed: cursor
  moves, clears, title changes, clipboard writes and the rest. No escape reaches your terminal from a tool, and copying the output copies
  its plain text. A background colour is not drawn, so the block's own shows.
- A compaction is a block of its own, folded by default, headed by what it did: `compaction · 182k → 3.1k tokens`, the tokens it read into the tokens
  of its summary, with its duration and status. Opened, it shows the summary, drawn as Markdown.
- An `edit` block, opened, shows the change as lines: `- ` before each line it removes, on a red tint, `+ ` before each line it adds, on
  a green one, and the lines it keeps between them. With `ui.highlight` on, the code is coloured by the file's language. Copying the
  block copies those lines.
- Scroll with the wheel or **Page Up**. The view stays on what you were reading while new text arrives, and the status line counts the lines
  below (`12 lines below`). Click that count, press **Page Down**, or **End** with an empty input, to return to the end.

## When the model asks you

The model can ask you up to sixteen questions at once, each with choices and room for a note. They appear above the input, as a
command's approval does, with a tab per question when there are several. When the headers don't fit on the row, the question shown
keeps its header and the others show their initial; with more still, the row shows those around the current one, and `‹` or `›` where
some are left out. A choice is marked `( )` when you pick one, `[ ]` when you may
check several. The note is the row after the last choice.

- **Tab** and **Shift+Tab** move between the tabs, the choices and the note.
- On the choices, **Up** and **Down** highlight one, and **Space** or its number selects it.
- On the tabs, **Left** and **Right** change question.
- On the note, you type as in the input; nothing you type reaches the note unless it has the focus.
- **Enter** goes to the next question and, after the last, to a review of every answer, which Enter sends and Esc leaves.
- **Esc** on a question declines them all, and the model carries on with its own judgement.

A click picks a choice, focuses the note, or opens a tab. The input below keeps what you had typed. `ask -p` never offers the model
this tool.

## Background jobs and threads

The model can run commands in the background, and `/thread` starts threads. The status line counts what is running (`· 1 thread · 2
jobs`). Click the count, or type `/jobs`, to list them below the input: Up and Down choose one, Enter shows its output (a thread's
conversation) in place of the conversation, and Esc, or a click on the list's first row, `main`, goes back. Jobs never outlive ask.

One list shows at a time: while the sidebar is shown, the list below the input is not. Below the input, jobs alone are a flat list; once a thread exists it is the same tree as the sidebar's. On a wide screen, `/sidebar`, **Ctrl+\\**, or a click on `«` in the top-right corner shows them beside the conversation, one row
each:

```
                                   »
◆ main
├ ⠋ thread-1 look into the parser   12s
│ └ ✓ thread-3 the lexer too
└ ✓ thread-2 check the pins

Jobs
⠋ #26a7 swift build -c release      3m
✓ #078c npm test

1 thread, 1 job running
```

The first row holds only the toggle: `»` closes the sidebar, and the `«` it leaves in the corner opens it again. `◆ main` is always
listed, so the panel does not move as threads and jobs come and go, and the last row says what is running and what waits for you.
Threads are a tree under the main conversation: `/thread` typed in a thread's lane starts one from that thread, under it. Each
row is a state mark (a spinner while it works; once it has done nothing for three seconds, its kind: `◇` a thread, `$` a job;
`?` waiting for you, `◌` waiting on its threads, `✓` done, `✗` failed, `■` stopped), the name, what it is doing, and how long an active one has run. Ended rows are dim, the one shown is bold, and
the one Up and Down chose is inverse; a click opens it, and `main` goes back.

Where the sidebar goes is `ui.sidebarLayout`. `"full"` puts it beside the transcript, its whole height, as above. `"bottom"` puts it
in a band with the input: six rows, more when it lists more (at most a third of the screen), the input on the left and the sidebar
on the right behind the same divider, so the transcript keeps the whole width; the status line's counts then sit at its trailing
edge, under the sidebar, instead of the sidebar's last row. `"adaptive"`, the default, takes the band where the full sidebar would
leave the transcript under 100 columns (a 120-column terminal), and the full sidebar on wider ones. Screens under 18 rows keep it
beside the transcript.

While a command the model ran is still running, **Ctrl+B** (or **Ctrl+Enter**, where the terminal reports it) sends it to the
background: the model gets what it printed so far and carries on, or your queued message is sent next, and the job tells the model
when it ends. With no command running, Ctrl+B moves the cursor as usual.

## Commands

| Command | What it does |
|---|---|
| `/model` | Choose the model, from every account you are signed in to. `/model NAME` sets it directly; `/model reset` undoes it. |
| `/thinking` | Choose how much the model thinks, among the levels it accepts. |
| `/login`, `/logout` | Sign in to or out of an account without leaving. |
| `/new` | Start a new conversation; the old one stays saved. |
| `/resume` | Switch to another saved conversation. |
| `/rewind`, `/fork` | Go back to an earlier prompt (also `/tree`), or continue in a copy. See [Sessions](sessions.md). |
| `/encrypt` | Encrypt this session's file (`/encrypt on`), or write it back in clear (`/encrypt off`). See [Sessions](sessions.md#encrypted-sessions). |
| `/tasks` | Show the session's task list, which the model keeps with its `tasks` tool: `/tasks all` with the done ones, `/tasks t3` for one task. |
| `#t3`, `#n2` | In a message, point at a task or a note: the model gets its text with the message. Type `#` at the start of a word to pick one. |
| `/notes` | `/notes TEXT` (or `/notes:add TEXT`) keeps a note as typed, with the time. `/notes` opens the picker to choose one and show it in the transcript; `/notes:all` (or `/notes all`) lists every note; `/notes:show n3` shows one; `/notes:edit n3` edits one in the input; `/notes:delete n3` removes one; `/notes:search TEXT` searches through all of them. The model reads them with its `notes` tool when you ask, or when it finishes a piece of work, and marks them acknowledged, fulfilled or dismissed; it never writes or edits one. |
| `/btw` | `/btw QUESTION` asks beside the conversation, even while a turn runs: the model answers from the conversation so far, without tools, in a cyan block, and the question and its answer do not join the conversation. |
| `/thread` | `/thread TEXT` starts a thread: a copy of the conversation as it stands (in a thread's lane, of that thread's, listed under it), marked by a block where it started, working on TEXT beside it with the same tools and sandbox. It is listed with the jobs (`/jobs`, then Down and Enter, or the sidebar); its lane shows its conversation, and what you type there goes to it. When it ends it stays as it is, idle, until you run `/merge` in its lane: ask never merges a thread on its own, nor asks to. Merging writes a summary of what it did with one more request, shown in the conversation it was started from as a folded block, which goes to the model with your next message; the threads under it merge first, into it. A merged thread is read-only. A subagent alone merges on its own when it ends, since the call that started it waits for its report. Threads are kept with the session: after `ask --continue` or `/resume`, merged ones come back read-only and unfinished ones stopped, continuing when you type in their lane; `/resume` lists conversations, not threads. What it asks you (an approval, the model's questions) is marked `?` in the sidebar, and main's turn ending does not decline it. By default (`threads.questions` `"focus"`) it shows at once wherever you are, named for its thread (`thread-1: …`), after your own conversation's questions; answering it there answers the thread. `"after"` waits `threads.questionsAfter` first; `"lane"` keeps it in its lane. In a thread's lane, Ctrl+C stops the thread and the threads under it (main's turn goes on) and asks once whether to merge them back in. `threads.max` and `threads.depth` limit how many work at once and how deep they nest. Switching sessions with threads at work asks first. Threads stop when ask quits. |
| `/threads` | Lists this session's threads, merged or not, by name, state and task; choosing one, or `/threads NAME`, shows its lane. |
| `/rename` | In a thread's lane, `/rename TITLE` names the thread. A thread is otherwise named by Apple's on-device model from its task, where it is available (`threads.names`), or numbered. |
| `/merge` | In a thread's lane, merges the thread back with a summary, and the threads under it: the only way a thread merges (a subagent aside). Refused while it works. `/close` is the same. |
| `/compact` | Summarise the conversation now to free room in the context window. |
| `/config` | Open the settings editor (`/config user` or `/config project`), or `/config show` to re-read the files and show them. |
| `/mcp` | Show the MCP servers and their tools. |
| `/reload` | Switch to a newer build of ask that appeared beside the running one, keeping the session; `/reload now` stops running jobs first. The new build must start (`--self-check`) and, when the running build is signed with a team's identity, be signed the same way: `Scripts/build-release.sh` builds and signs. |
| `/skill:NAME` | Ask for a skill by name. |
| `/jobs`, `/sidebar` | Show the background jobs. |
| `/verbose` | Show or hide details: the sandbox in force, the files read. |
| `/help` | List the commands. |
| `/quit` | Leave. |

While the model works, commands still work:

- `/model`, `/thinking`, `/config` and `/mcp` at once: a new model, effort or setting applies from the very next request, even in the
  middle of a run of tool calls, and a retry waiting on a busy model goes to the new one at once.
- `/login` and `/logout` at once; signing out of the account the turn uses waits for the turn to end.
- `/notes` and `/tasks` at once, without reaching the model; `/btw` and `/thread` at once, beside the turn.
- `/fork` at once: the copy holds what the turn has written so far, and you stay with the turn; `/resume` switches to the copy.
- `/compact`, `/new`, `/resume`, `/rewind`, `/encrypt` and `/reload` wait for the turn to end, shown as waiting, then run in the order you typed
  them. If you stop the turn, they follow `ui.queuedOnStop` like queued messages: with `none` they come back to the input.
- `/skill:NAME` is a message, so it joins the turn like any other.
