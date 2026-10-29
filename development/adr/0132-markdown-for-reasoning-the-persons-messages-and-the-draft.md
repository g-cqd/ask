---
status: accepted
date: 2026-10-29
---

# 0132 — Markdown for reasoning, the person's messages and the draft

## Context

ADR-0129 drew the model's replies as Markdown and left the person's messages, the reasoning and the draft as written. The owner asked for
Markdown everywhere it can be (roadmap 0151); 0085's research had already specified colour for the draft.

## Decision

1. **Reasoning and the person's messages** go through the reply renderer (`ScreenComposer.markdownItemLines`). Each keeps its look under
   every mark: reasoning dim and italic, the person's message bold, merged into each run's style (accents replace the row's style, so the
   look is added to them, not assumed). Open reasoning keeps its status and duration at the right edge of its first row, on a row of its
   own when the first is too full. Folded reasoning is still one line. Copy takes the source through the rows' segments, as for replies.
2. **The draft is coloured, never rewritten** (`InputMarkdown`): one parse, then each text leaf takes the reply theme's style for the
   containers around it, and every byte no leaf covers that is not a space is a marker, drawn dim. A setext heading is left plain (its
   meaning comes from the line after it). The spans become accents on the drawn rows through `InputLayout` positions, so the cursor,
   selection and copy are untouched; the input's tint stays behind them.
3. **A long draft is parsed only around the rows shown** (over 8 KB): from the last line before the window that follows a blank line
   outside any fence and is not indented, to the end of the last line shown. A test compares the window's colours with the whole parse's
   on a 1,500-line draft of every construct, at 14 windows; mutations of the restart rule (ignoring indentation, not requiring a blank
   line) turn it red.
4. All of it follows `ui.markdown`; off is drawn as before.

## Measured

A keystroke after pasting a Markdown-heavy draft, release, pyte, 25 keystrokes each, loaded machine:

```
draft   2500 B markdown off: keystroke median  0.82 ms p90  1.00 ms
draft   2500 B markdown on : keystroke median  1.32 ms p90  1.52 ms
draft  10000 B markdown off: keystroke median  1.97 ms p90  2.27 ms
draft  10000 B markdown on : keystroke median  2.31 ms p90  2.52 ms
draft  20000 B markdown off: keystroke median  3.49 ms p90  3.94 ms
draft  20000 B markdown on : keystroke median  4.09 ms p90  4.46 ms
draft  46000 B markdown off: keystroke median  4.01 ms p90  7.70 ms
draft  46000 B markdown on : keystroke median  5.33 ms p90  7.76 ms
```

The first version parsed the whole draft and kept a `Style` per byte: +2.5 ms at 46 KB, and 20 KB went from 3.55 to 4.70 ms, past the
4 ms budget. A byte-sized style index and the window brought the extra to 0.15 to 0.6 ms up to 20 KB and 0.7 to 1.3 ms at 46 KB, over two runs.
At 20 KB the median with Markdown was 3.65 ms in one run and 4.09 ms in the other (3.49 to 3.50 without): at the edge of the budget.
Drafts over about 20 KB were over budget before this (0085 proposal 5); an incremental `InputLayout` and parse are what would fix both.

## Consequences

- Tool output stays raw: its characters matter, and its code is for highlighting (0152).
- Not seen in a real terminal yet.
