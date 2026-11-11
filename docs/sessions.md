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

A conversation gets a short name from your first message, and a new one after each compaction, from what it kept. Apple's
on-device model writes it, so it costs nothing; where that model is not available (an older Mac, or Apple Intelligence off) the
conversation has no name. The name is saved with the session. The terminal's tab reads `ask · name`, or `ask · folder` while there is
no name, and gets its own title back when ask closes; the session lists show the name before the first message.

A session remembers the account it used and resumes on it. On exit, ask prints a command to resume the saved session in its
working directory, retaining the launch flags and safely escaping spaces and shell metacharacters.

ask works in the folder it is started in, and `/reload` starts the newer build in that same folder. If the folder was replaced under
your shell (removed and made again, or its volume mounted again), ask goes back to it and says so; when it is not there at all, ask
says that and stops, and `/reload` stays on the running build.

## Going back, and branching

`/rewind` (or `/tree`) lists the prompts of this session, numbered. `/rewind N` goes back to just before prompt N and puts that prompt in the input: edit it
and send, and the conversation continues from there as a new branch. Nothing is deleted; the earlier branch stays in the file.

`/fork` continues the conversation in a new session file, leaving the original untouched. `/fork N` does so from before prompt N.

## When the conversation gets long

A model can only read so much at once (its context window). When the conversation reaches 75% of the window, ask summarises the earlier part
and keeps the recent messages word for word, then carries on. `/compact` does it now. The threshold is the `compactAt` setting
([Configuration](configuration.md)): a share up to 1 such as `0.6`, a number of tokens such as `100000`, or `0` to wait until the window is full.

## Encrypted sessions

Sessions can be encrypted, compressed, or both (`sessionEncryption`, `sessionCompression`, `sessionPassword` in
[Configuration](configuration.md)). The first time you start ask, it asks once the screen is up: encrypt your sessions, and keep the key
in your keychain? Choosing to encrypt sets a password (typed twice, never shown) and shows a recovery code once; it opens your sessions if
you forget the password, and leaves the screen when you press Return. Closing the question with Esc keeps this run's session plain and
asks again next time.

An encrypted session opens only with your password, the recovery code, or the key kept in your keychain. `/encrypt on` encrypts the
session you are in (opening or setting up the keys first, in the screen); `/encrypt off` writes it back in clear. `ask keys password`
changes the password, and `ask keys forget` removes the key from your keychain. The session's task list and notes are kept the same way
as the session. `ask sessions` lists sessions it cannot open as locked.
