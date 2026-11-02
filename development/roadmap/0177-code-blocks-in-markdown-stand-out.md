---
status: done
blocked-by: []
date: 2026-11-01
---

# 0177 — Code blocks in Markdown stand out at a glance

Wish (2026-11-01): code in Markdown is not visible enough; maybe show its first line as a snippet when folded, a stroke around it,
an interactive title, or better indentation.

## Done (2026-11-01)

- Four looks mocked on dark and light pages (A today, B a tinted band, C a left rule, D a title row); the owner chose **C**.
- TerminalKit `7e265cf`: `MarkdownTheme.codeOpen`, `codeClose`, `codeRule` draw a block inside a rule; unset (TerminalKit's own
  themes), a block is drawn as before. The corners and the rule carry no source, so a selection copies the code alone.
- ask's theme (`ScreenComposer.markdownTheme`): `╭─ swift` on the language's row, a dim `│ ` down the gutter, `╰─` after the code. A
  folded long block keeps its fold title (`code · swift · 4 lines`), which stands in for the corner when it is opened.
- Tests: TerminalKit's `MarkdownCodeRuleTests` (3 mutants, all killed); ask's `CodeRuleTests`, and the tests and three row digests that
  pinned the old look, updated on purpose.
- Not done: the fold title drawn as the corner (`╭─ swift · 4 lines`), and a look in a real terminal.
