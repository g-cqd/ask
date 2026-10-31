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

- TerminalKit `Style.link` (OSC 8): a cell's style can carry a URI; the diff opens and closes the link where it
  changes and at the end of a frame, and never sends a URI with a control character, a space or a non-ASCII byte.
- `PathLinks` in `AskTUI`: tool-block rows (header, input, output) link `/…` and `~/…` words, without a trailing
  `:line:col`, computed once per block layout. Tests in `PathLinksTests` and TerminalKit's `HyperlinkTests`.

- Owner report (2026-10-29): hovering one path lit up every copy of it in the block, and clicking a link opened nothing. Fixed:
  - TerminalKit `dad2cd6` `Style.linkID`: OSC 8 `id=`, only letters, digits, `-_.`; ask gives each link an id from its screen
    row and column, so two copies of one path are two links (`LinkIdentityTests`; checked in a PTY: `id=ask-24-6` and `id=ask-24-24`
    for one path twice).
  - A single click on a link opens it (`Effect.openLink`, `LinkOpener` through `NSWorkspace`): web pages, `mailto:`, documents and
    folders in their apps. A file that would run (an app, a script, an executable, an installer) is shown in the Finder instead; other
    schemes are not followed; a refusal is said in the status line. A double click still selects the word; a click beside a link still
    folds. With the mouse on, the terminal's own link handling never sees a click, which is why nothing opened.
  - Web addresses (`http(s)://`, balanced parentheses kept, sentence punctuation dropped), `mailto:` and bare email addresses are
    linked beside paths (`AddressLinks`), in every block, not only tool rows; a `git@host:org/repo` remote is not an email.
  - The plain-assistant characterisation digest was re-pinned after proving that, without links and the new style field, it is the
    old one.

## Still owed

- Not seen in a real terminal: the escape sequences were checked in a PTY's bytes, not in the owner's terminal; a click opening an app
  was not run (it would open one on this Mac).
- The row keeps the text the tool printed (an absolute path stays absolute): showing `~/…` would change wrapping and
  the selection's text, so it is not done.
- Relative paths are not linked (a row does not know its directory); a path wrapped over two rows links only the part
  on each row; no `id=` parameter joins them for hover.
- ask pins TerminalKit at e0b13ab, which is pushed.

## Closed (2026-10-31)

Paths in tool rows, bodies and the exit banner open on click (absolute paths, OSC 8). What "Still owed" lists is either a check in a
real terminal, moved to the list in `research/priorities-2026-10-31.md`, or a choice made and explained there: rows keep the path as printed, relative paths are not
linked, and a wrapped path has no `id=`. Those come back as new entries if the owner asks.
