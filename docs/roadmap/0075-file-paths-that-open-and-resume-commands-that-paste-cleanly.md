---
status: done
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

## Still owed

- File hyperlinks in tool headers/bodies and diagnostic locations within the
  interactive transcript (separate UI block link integration).
