---
status: in-progress
blocked-by: []
date: 2026-10-27
---

# 0075 — File paths that open and resume commands that paste cleanly

File paths shown on session exit use terminal hyperlinks (OSC 8) to the actual
file with an absolute `file://` URI while displaying a short path using `~` inside
the user's home directory. The resume command outputs unquoted `ask`, unquoted
`--resume`, unquoted flags, and backslash-escaped path components that preserve
leading unquoted `~` so bash, zsh, and fish can expand it cleanly upon paste.

## Done

- `PathDisplay` in `AskAgentCore/Session`: `tilde` path formatting, OSC 8
  `link(to:display:)` hyperlinks, and paste-safe `shellArgument(_:home:)`.
- `AgentConversation.printResumeCommand()`: prints clickable terminal hyperlink
  displaying `~/…` and a clean `cd <workspace>; ask --resume <session> <flags>`
  command without outer single quotes breaking tilde expansion.
- `Scripts/probe-resume-banner.py`: PTY probe verifying the OSC 8 sequence,
  unquoted command, and expandable tilde session argument.

- TerminalKit `Style.link` (OSC 8): a cell's style can carry a URI; the diff opens and closes the link where it
  changes and at the end of a frame, and never sends a URI with a control character, a space or a non-ASCII byte.
- `PathLinks` in `AskTUI`: tool-block rows (header, input, output) link `/…` and `~/…` words, without a trailing
  `:line:col`, computed once per block layout. Tests in `PathLinksTests` and TerminalKit's `HyperlinkTests`.

## Still owed

- Not seen in a real terminal: the escape sequences are tested as bytes, no PTY probe of the transcript yet.
- The row keeps the text the tool printed (an absolute path stays absolute): showing `~/…` would change wrapping and
  the selection's text, so it is not done.
- Relative paths are not linked (a row does not know its directory); a path wrapped over two rows links only the part
  on each row; no `id=` parameter joins them for hover.
- ask pins TerminalKit at e0b13ab, which is pushed.
