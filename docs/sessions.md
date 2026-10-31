# Sessions

Every conversation is saved as it happens, one file per session, under `~/.local/state/ask/sessions/` (or `$XDG_STATE_HOME/ask/sessions/`),
grouped by project. A message counts as sent only once it is written there, so a crash loses nothing you were told was sent.

## Coming back to a conversation

| From the shell | Inside ask | What it does |
|---|---|---|
| `ask -c` | | Continue the last conversation in this project. |
| `ask -r` | `/resume` | Choose one from a searchable list. |
| `ask -r NAME` | `/resume NAME` | Resume one directly, by name, a unique prefix of it, or a path. |
| `ask sessions` | | List this project's sessions, newest first. |
| | `/new` | Start a fresh conversation; the current one stays saved. |

A session remembers the account it used and resumes on it.

## Going back, and branching

`/rewind` (or `/tree`) lists the prompts of this session, numbered. `/rewind N` goes back to just before prompt N and puts that prompt in the input: edit it
and send, and the conversation continues from there as a new branch. Nothing is deleted; the earlier branch stays in the file.

`/fork` continues the conversation in a new session file, leaving the original untouched. `/fork N` does so from before prompt N.

## When the conversation gets long

A model can only read so much at once (its context window). When the conversation reaches 75% of the window, ask summarises the earlier part
and keeps the recent messages word for word, then carries on. `/compact` does it now. The threshold is the `compactAt` setting
([Configuration](configuration.md)): a share up to 1 such as `0.6`, a number of tokens such as `100000`, or `0` to wait until the window is full.
