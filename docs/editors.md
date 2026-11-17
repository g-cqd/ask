# ask in an editor

`ask serve` is ask without its screen: an editor starts it and speaks to it over the
[Agent Client Protocol](https://agentclientprotocol.com) (ACP), on standard input and output. The editor draws the conversation, its
tool calls and its questions; ask does the work, with your configuration, your accounts, your sandbox and your skills.

## Setting it up

Sign in at a terminal first (`ask login …`, see [Getting started](getting-started.md#sign-in)): `ask serve` signs nobody in.

Then name ask as an agent in your editor, as the command `ask` with the argument `serve`. Zed's documentation gives this shape for a
custom agent, in its settings:

```json
{
  "agent_servers": {
    "ask": { "type": "custom", "command": "/Users/you/.local/bin/ask", "args": ["serve"] }
  }
}
```

Write the full path to ask when the editor does not start programs with your shell's `PATH`.

ask is checked against the protocol by a client of its own and by the protocol's compatibility kit. It has not yet been run under
each editor: what an editor draws for a given message is that editor's.

## What a session is

Each thread the editor opens is an ask session, in the folder the editor names for it, whatever folder `ask serve` was started in.

- **The model** is the one your [configuration](configuration.md) gives that folder (`provider`, `model`). There is no picker yet.
- **The sandbox** is the folder's, as on the screen: see [The sandbox](sandbox.md).
- **It is saved** as it happens, with the other sessions of that folder, and the editor can open it again. A session open in another
  ask is refused, saying so. An [encrypted](sessions.md#encrypted-sessions) session whose keys are not open is refused too: ask never
  asks for a password through an editor, so run `ask --resume ID` at a terminal once.
- **Several sessions** run in one `ask serve`, each with its own folder, task list, notes and background jobs. When the editor goes
  away, ask stops what its sessions left running and ends.

## What the editor shows

- **The model's words and its thinking**, as they arrive.
- **Each tool call**, as it begins and as it ends, with what the model asked for. A `write` is shown as a diff of the file: the text it
  replaces and what replaces it, or a whole file as added.
- **A command that goes on** after its call has ended (a `bash` call that yields) keeps being told on that call as it prints, even
  after the turn has ended, and then how it ended.
- **Approvals.** When a call needs your consent, the editor asks you, with the answers the screen offers (this time, for the
  session, no). [`approvals`](configuration.md#approvals) in your configuration decides what is asked, as it does on the screen.
- **The model's questions**, as a form, in an editor that shows forms. In one that shows none, the model is not offered the
  `question` tool: it has to decide, or ask in its answer.
- **Stopping.** Cancelling the turn in the editor stops the model and the command it was running.

## What you can type

A prompt is text, with the files the editor attaches as links. Pictures are not taken yet.

Three of the screen's commands work as a prompt:

| Prompt | What it does |
|---|---|
| `/tasks` | Shows the session's task list. |
| `/compact` | Summarises the conversation so far to make room. |
| `/skill:NAME request` | Sends the request with that skill attached. |

An editor that lists an agent's commands is told these, and your skills. To send the model the text and not run the command, type two
slashes: `//tasks` reaches it as `/tasks`. Any other prompt that starts with a slash is sent as it is. The screen's other commands
(`/model`, `/rewind`, `/fork`, `/goal`, …) are not served yet.

## MCP servers

The MCP servers the editor is configured with are given to each session, beside the ones in your own
[configuration](skills-and-mcp.md#mcp-servers):

- A program is started in the session's folder; a server at a URL is spoken to over HTTP.
- A server of the editor's replaces one of yours with the same name, for that session.
- Its tools are named `mcp__NAME__tool`, with the characters a tool's name cannot hold replaced: `My Server` is `My-Server`.
- A server ask cannot run (one spoken to over SSE, one with no command and no address) is left out, and the session goes on without
  it. An editor that shows notices says which.
