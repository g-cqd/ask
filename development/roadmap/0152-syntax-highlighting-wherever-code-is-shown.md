---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0152 — Syntax highlighting wherever code is shown

Owner (2026-10-29): "files with known language or piece of code are not necessarily syntax highlighted"; "syntax highlighting — we
should plan for all that." Today nothing in ask is highlighted: TerminalKit's Markdown renderer takes a highlighter
(`MarkdownCodeHighlighter`) and ask passes none, so a fenced block shows its language label and plain lines. 0065 phase 5 planned
Atelier's lexers and 0087 their promotion; neither was built.

## What exists

- **Atelier's `AtelierLexers`** (585 lines, plus 1,303 of scanners: code, CSS, data, HTML): hand-written, line-resumable scanners over
  borrowed UTF-8, from an entry state per line (`LexState`), for the 20 languages of `AtelierSyntaxModel.Language` (Swift, Objective-C,
  Kotlin, Java, JavaScript, TypeScript, C, C++, Python, shell, fish, HTML, CSS, JSON, YAML, TOML, Rust, Go, Ruby, Lua) and plain text.
  Line-resumable is what streaming and the windowed input parse need: a line's colours depend only on the state the previous line left.
  It depends on `AtelierHighlighting` and `AtelierSyntaxModel` (Atelier) and `TerminalKitText`.
- **TerminalKit's hook**: `MarkdownCodeHighlighter`, colours per line of a fenced block, by the fence's first word.
- **AemiUnicode** now has identifier-grade Unicode data (binary properties: `ID_Start`, `ID_Continue`), which lexers need for
  identifiers beyond ASCII.

## Where code is shown in ask

| Place | Language from | Phase |
|---|---|---|
| Fenced code in replies, reasoning and the person's messages | the fence's info string | 2 |
| `read` output (file contents) | the file's extension, then its first line (`#!`) | 3 |
| `write` and `edit`: the content and the diff | the path's extension | 3 |
| Code shown in the draft (fences while typing) | the fence's info string | 4 |
| `bash`: the command in the block's header | shell | 4 |
| Tool output that is code (`git diff`, JSON) | a diff and JSON recogniser on the output | 5 |

## Phases (each red first)

1. **Promote the lexers to aemi**, as `AemiSyntax` (0087's AemiLexers, inside a broader package only when a second piece joins it):
   `Language`, `LexState`, the scanners and the token roles, without Atelier's highlighting model; Atelier then depends on it (the pin
   chain of aemi ADR 0018, once). Tests move with them; a per-language corpus of tricky lines (raw strings, nested comments, heredocs,
   template literals) with expected roles, compared before and after the move.
2. **Fenced code everywhere Markdown is drawn**: a `MarkdownCodeHighlighter` over the lexers, roles to a theme that follows the system
   appearance (0108) and the block tint. Streaming: a growing block is lexed from its last complete line's state, never from the top.
3. **Files**: `read`, `write`, `edit` and their diffs, the language from the path. A diff keeps its `+`/`-` colour behind the tokens.
4. **The draft and command headers**: fences in the draft (through 0151's window: the lexer resumes from the fence's opening line), and
   the shell command of a `bash` block.
5. **Recognised output**: unified diffs and JSON in tool output, by content, never guessing a language otherwise.

## Budgets and limits

- Lexing on the main actor costs at most what Markdown does per block (ADR-0132's measure); input stays within 4 ms with a fence in the
  draft; a 1 MB `read` is highlighted for the rows shown, not the whole file.
- `ui.highlight` on by default, off draws as today, byte for byte (a characterisation test before the change).
- A language the lexers do not know is plain, never approximated by another.
