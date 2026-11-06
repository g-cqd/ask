---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0151 — Markdown everywhere it can be: reasoning, the person's messages, and the draft

Owner (2026-10-29): "markdown should have been applied to input as well, and we should have it on thinking blocks and wherever possible";
"first steps can be markdown rendering everywhere". The wish of 10-25 (line 11) asked for the input coloured as Markdown while typing,
characters kept; 0085's research specified it (proposal 4); ADR-0129 drew replies only and left the prompt and reasoning out.

## Built (ADR-0132)

- **Reasoning**, open, through the reply renderer, its dim italic look kept under every mark, its status on the first row.
- **The person's messages**, through the same renderer, bold kept under every mark.
- **The draft**, coloured only: marks in the reply theme's styles, markers dimmed, setext headings left plain; a long draft is parsed
  only around the rows shown.
- All three follow `ui.markdown`; off is drawn as before. A selection copies what was written.

## Where Markdown does not go, and why

- **Tool output and tool input**: what a program printed or was given, shown as it is; Markdown would hide characters that matter
  (`*` in a glob, `#` in a shell comment). Its code is for syntax highlighting (0152).
- **ask's own notices**: plain sentences ask writes; nothing to render.
- **`ask -p` and pipes**: raw by design (0065).
- **Queued prompts**: still drawn as typed; a small follow-up, through the same path as the person's messages.

## Still owed

- ~~Queued prompts~~ Done (2026-11-05, note n43): drawn as Markdown, as sent ones are. Still owed: the real-terminal look of all
  three (pyte only so far), which is the owner's.
- ~~Drafts over about 20 KB past the 4 ms input budget.~~ Done, 2026-11-01, without an incremental layout: what cost the time was
  linear walks, now cheap. TerminalKit's `InputLayout` lays a run of printable ASCII out a row at a time (TerminalKit `40b7d8a`, an
  equivalence test over 600 random drafts against the grapheme walk): 0.72 → 0.056 ms at 21 KB, 7.16 → 0.55 ms at 217 KB. The draft's
  parse window finds its start by a byte scan while the text before it is ASCII, and its restart point reading the bytes in place
  through the string's own span. A keystroke's whole frame (release, M3, 120 columns): 21 KB 1.09 → 0.17 ms with paragraphs (0.39 ms
  as one long list), 217 KB 10.9 → 1.47 ms with paragraphs (3.55 ms as a list with no blank line, which the window cannot cut).
- Found on the way: in a draft with CRLF line endings, the Markdown colours were shifted from the first `\r\n` on. Spans mapped a
  byte to a character for any ASCII text, and `\r\n` is one character of two bytes; fixed, and pinned by a window-against-whole
  test on a CRLF draft, beside one with accents and emoji.
