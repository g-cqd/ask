---
status: in-progress
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

## Progress (2026-10-31)

**Phase 1, done.** The lexers are `AemiLexers`, a module of aemi (aemi ADR 0022, `61b67bc`; the owner chose a module over 0087's own
package), then three gaps closed red first (`6e8279c`): an exponent's sign is part of the number, Rust raw strings (`r#"…"#`, any
level), Lua long strings (`[[…]]`, `[==[…]==]`), each checked by a whole-text scan and a line-by-line scan of 29 tricky lines. Release
throughput is unchanged (median ratio 1.00 over the corpus, Rust within 2 %). The pin cascade carried aemi `6e8279c` to ask (`814d97e`). Atelier
consumes the module since its `41e0ec0` (0087, done).

**Phase 2, done.** `CodeHighlighter` (AskTUI) is the renderer's `MarkdownCodeHighlighter`: the fence's language through
`Language(name:)` (aliases such as `sh`, `c++`, `js` resolve; an unknown name or `plain` gives nil, so the block draws plain), each line
lexed from the state the previous one ended in, and each role, or the nearest role above it, given a palette colour: keyword 5, string
2, number and escape 3, attribute and tag 4, type and property 6, comment dim italic. The palette is the terminal's, so the colours
follow its theme and the system appearance. `ui.highlight` (default on) turns it off; off is pinned by a digest taken before the
change (`CodeHighlightCharacterisationTests`, 5 messages × 80 widths × 2 looks).

Measured (release, M3) with a 38,858-byte reply holding a 400-line Swift block at 120 columns: the whole message renders in 24.7 ms with
highlighting off and 29.8 ms on, +5.1 ms. The hook itself is 0.22 ms; the rest is TerminalKit's `BlockWriter+Code.pieces`, which
cuts a piece at every token, and ask's conversion of styled pieces to accents.

**Deviation from the plan.** The plan had the lexer resume from the last line while a fence streams in. The renderer's hook is
stateless and gets whole blocks, and each streamed delta lays the message out again (rows are cached per revision), so there is
nothing to resume from. Lexing is 1 % of that re-render, so resuming would save nothing measurable; the per-token piece cost is the
follow-up, in TerminalKit (merge adjacent pieces of one style) and in ask's accent conversion.

**Render cost, 2026-10-31.** `MarkdownRenderBenchmark` (`ASK_RENDER_BENCH=1`, release, M3; 38,479-byte reply, 400-line Swift block, 120
columns) times each step. Composing the message, before → after, in ms: highlighting off, folded 2.90 → 0.73, open 7.45 → 1.45;
highlighting on, folded 3.65 → 0.73, open 9.52 → 2.78. Four changes, each pinned by a digest or an oracle taken from the code before it:
- links: `LinkCandidates` skips, from the bytes, the rows that cannot hold a path or an address; the finders had walked every row
  holding a `/` or `:` character by character, which was half the compose (`LinkFinderCharacterisationTests`, 20,000 random lines);
- folds: a folded block is its header alone, no longer laid out and coloured only to be dropped; its fence is found from the block's
  first leaf rather than its first row, which also folds a block whose first line is blank, which did not fold before
  (`CodeFoldCharacterisationTests`);
- lines: `LineSplit` finds the fences' lines from the bytes, as the character split did (`LineSplitTests`);
- TerminalKit `686bdc9`: string widths and the wrap's glyphs take printable ASCII a byte at a time (its oracle tests). Measured with it
  through a local edit; ask resolves it once the pin cascade carries it.
Then the row conversion stopped measuring a row's merged segment again for every run (`SegmentEnd` carries its end column and
linearity; `MarkdownRowCharacterisationTests`, 400 random messages), and TerminalKit `92cd9e7` cuts code lines without a set and
allocates rows once: open, highlighted 2.78 → 2.34 ms. What is left in the open, highlighted case is the renderer (`BlockWriter.emitCode`: the wrap, `pieces`' cut set) and ask's row
conversion (`line(of:block:inset:source:)`).

**Known gaps** (the lexers', drawn plain or partly coloured, never wrongly as another language): Swift and JavaScript regex literals;
JavaScript template literals nested inside `${…}`; Python's `f`/`r` prefix is outside the string token; C++ `R"(…)"` takes `R` as a
type; Ruby `%w[]` and `:symbol`; HTML `<script>` and `<style>` bodies; Lua level comments `--[==[ … ]==]`.

Phases 3 to 5 remain.
