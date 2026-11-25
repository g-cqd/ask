---
status: accepted
date: 2026-10-22
---

# 0063 — Long code folds inside the reply, and is found by its fences

## Context

ADR-0044 and ADR-0046 promised that a long code block folds to a placeholder, from a count showing 91% of 725 code blocks are 20 lines
or fewer. Thinking and tool output fold because each is its own transcript item. Code is not: the model writes it **inside** an
assistant message that streams, and the message must stay one item (its text is what the session records and what a selection reads).

## Decision

- A block is a CommonMark fence: up to three spaces of indent, three or more backticks or tildes; it closes on the same character,
  at least as many, with nothing after it. An info string containing a backtick does not open a backtick fence. An unclosed fence
  runs to the end of the text, so a block streaming in is measured as it grows. Indented code is not recognised.
- A block **longer than** `ui.codeFoldLines` (default 20, never more than half the screen's rows, so a short window folds sooner)
  starts folded to one dim line: `code · swift · 34 lines`, or `code · 34 lines` without a language. Nothing is hidden without a
  placeholder (ADR-0044).
- Each long block has its own state, named by the message and its place among that message's fences. A click on the placeholder
  opens it; a click on an open block's **opening fence** folds it again. A click in the code or in the text around it only selects.
  `ui.code` (`"folded"` or `"open"`, default folded) and Ctrl+G flip every long block, forgetting the individual choices, like
  Ctrl+T and Ctrl+O.
- What is shown is what is selected and copied: a folded block copies as its placeholder, an open one as its fences and code.
  The session still records the model's text untouched; folding is a view.
- The fold is computed once per changed item on layout, and its text feeds both the rows drawn and the lines a selection reads. A
  message with no run of three backticks or tildes is rejected by one pass over its bytes, with no allocation.
- Opening or closing keeps the reader's place the way tool folds do (the scroll position moves by the height change).

## Consequences

A message that streams a long block is laid out again on every delta, as before; the scan is linear in the message. An open block
that is still being written and passes the limit folds the moment it is long enough, **unless the user opened it** — a block's
choice is keyed by its ordinal, which does not change while text is only appended.

**Not done:** images. ask has no image content to draw or fold yet; `ui.images` stays refused rather than accepted and ignored. Indented
code blocks, and code in tool output (which already folds as output), are not covered. Terminal height changes alter the limit and
lay out messages that hold a fence.
