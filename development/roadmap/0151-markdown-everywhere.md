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

- Queued prompts; the real-terminal look of all three (pyte only so far).
- Drafts over about 20 KB were already past the 4 ms input budget before this (0085 proposal 5, an incremental `InputLayout`).
