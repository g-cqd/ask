# Wrapping prose, and Markdown colour in the input (roadmap 0085, 2026-10-29)

Machine: Apple Silicon, release builds, loaded (the medians move by about 10% between runs). Everything below was run at ask `2d6bb5c`,
TerminalKit `be91ed8` and AemiMarkdown `2e75a94`, with a scratch test (wrap examples, not kept) and a scratch package `/tmp/mdinput`
(costs and parse states, not kept). Its findings need decisions from the owner, so no roadmap entry is filed yet: see "Proposed entries".

## Which wrap draws what

| Where | Wrap | Breaks at |
|---|---|---|
| The input (`PromptLayout` → `InputLayout`) | by character | any grapheme: `e│nough`, `sec│ond` |
| Your messages, tool output, Markdown-off replies, headers (`TextWrap.rows`) | by word | spaces; inside a word only when the word alone is too wide |
| Markdown replies (`RowWrap`, TerminalKitMarkdown) | by word, across styles | spaces; hanging indent under list markers and quote bars |
| Code (Markdown fences, `ScreenComposer+Code`) | by character | any grapheme, which is right for code |

## Where it looks wrong (rows as drawn)

1. **The input breaks words.** Width 24, `- an item that is long enough to wrap onto a second row`:
   `- an item that is long e` / `nough to wrap onto a sec` / `ond row`. Every editor people know wraps at words.
2. **A token wider than the row leaves its line almost empty.** Width 40, `see https://github.com/…/ScreenComposer%2BMarkdown.swift for details`:
   `see` / `https://github.com/g-cqd/ask/blob/main/S` / `ources/…`. The token is cut anyway; moving it to a new row only wastes `see`'s
   row. Same for paths (`I changed` alone, width 30).
3. **Chinese and Japanese text is one long word.** Width 24, `Note: 日本語の長い文章を…`: `Note:` alone, then the ideographs. They may
   break between any two characters (UAX #14 class ID); today a run of them is a word, moved whole to the next row, then cut by width.
4. **No break after a hyphen.** Width 20, `the well-known-hyphenated-compound-word-that-is-long ends`: `the` / `well-known-hyphenate` /
   `d-compound-…`. After `-` between letters is a break opportunity (UAX #14 HY).
5. **No hanging indent outside Markdown.** Your messages and Markdown-off replies: a list item or a quote continues at column 0
   (`- an item that is long` / `enough to wrap…`; `> a quoted line…` / `long enough…`), and so does an indented line
   (`    let value =` / `compute(argument,`). Markdown replies already indent under the marker and repeat the bar.
6. **Fine as is:** wide characters (two columns, never split), emoji ZWJ sequences and flags (one grapheme, two columns; how each terminal
   draws them is unverified), two spaces after a full stop (one is the break, a trailing space is invisible).

## Where a better wrap belongs

- **Break opportunities** (which positions may break: spaces, after a hyphen between letters, between ideographs, after `/` or before `?`
  in a token wider than the row) are a Unicode algorithm with no notion of width: **AemiUnicode**, beside its generated tables, as roadmap
  0076 asks. Aemi has no line-break property today (`AemiUnicode`: case folding, NFD, sets; `AemiText`: a tokenizer). A subset of UAX #14
  (BA, HY, ID, SP, plus the URL rule above) is enough; the full pair table is not needed.
- **The wrap to a width** stays in **TerminalKitText**, which owns `UnicodeWidth`. One walk for `TextWrap`, `InputLayout` (as an option)
  and TerminalKitMarkdown's `RowWrap`, so the three cannot disagree on where a row ends.
- Not AemiMarkdown: the parser knows no width and should not.

## Markdown colour in the input

Colour only: the text stays as typed (`*`, `#`, backticks stay), so editing, the cursor and copy are untouched.

### Cost per keystroke (a character typed mid-draft, full re-parse, median of 200)

| Draft | Parse + styled ranges | `InputLayout` (paid today) |
|---|---|---|
| 2.5 KB, 91 lines | 24 µs | 81 µs |
| 46 KB paste, 1,621 lines | 0.37 ms | 1.4 ms |

Colour adds about a quarter of what the input already costs. Both fit the 4 ms input budget at 46 KB. Like the layout, the parse is cached
by text, so a cursor move costs nothing. The layout's 1.4 ms on a large paste is the bigger number: it is rebuilt whole on every edit, and
rebuilding from the edited hard line would make it proportional to that line.

### What changes while typing (AemiMarkdown's parse of each state)

| Typed | States |
|---|---|
| `- a` under a line `Title` | `-` and `- ` make **`Title` a heading** (a setext underline), then `- a` makes it a paragraph and a list |
| `***bold***` at a line start | a list item, text, **a rule**, text, strong, then emphasis and strong |
| a fence above existing text | everything below it becomes code until the fence is closed |
| `see **bold**` | `**` as text, then `bold*` italic with a stray `*`, then bold |
| `# a` | `#` is an empty heading, `#a` text, `# a` a heading |
| `2. a` under a line | text (only `1.` may interrupt a paragraph) |

The first three change lines other than the one being typed, which reads as flicker. The others change only the span being typed.

### Proposal

- **Coloured:** ATX headings, emphasis, strong, strikethrough (markers dimmed), code spans and fences (code colour), links (text in link
  colour, target dimmed), list and quote markers (dimmed).
- **Not coloured:** setext headings and rules, the two constructs whose meaning is set by a later line (`-`, `---`, `***`).
- **An unclosed fence** colours its info string and the lines down to the cursor, not the rest of the draft; a closed fence colours its
  whole block.
- **Cursor and selection:** unchanged. Styles are per cell on the same rows; `InputLayout` positions do not move; the selection's inverse
  is drawn over them as over plain text.
- **Switch:** the same `ui.markdown` as replies, or a separate key; owner to choose.

## Proposed entries (for the owner)

1. Word wrap in the input (`InputLayout` option, TerminalKit), and a token wider than the row starting where it is, in all three wraps.
2. Break opportunities from AemiUnicode (UAX #14 subset) used by the one TerminalKit walk: ideographs, hyphens, long URLs and paths.
3. Hanging indent in `TextWrap` for your messages and Markdown-off replies: under `- `, `* `, `1. `, `> ` and leading spaces.
4. Markdown colour in the input as proposed above.
5. `InputLayout` rebuilt from the edited line, not the whole draft, when a paste is large.
