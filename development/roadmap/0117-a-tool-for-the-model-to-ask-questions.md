---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0117 — A tool for the model to ask the person questions

Owner wish (2026-10-28 20:33): a tool the model calls to ask one question or a series, each with multiple choices, single or multiple
selection, plus a free-text note that counts as an answer on its own or in addition to the choices.

## Owner's sketch

- The questions sit as tabs at the bottom of the screen, above the input, never hiding it.
- Focus moves between tabs, options and the note with Tab, the arrows, or a click; Space selects a choice.
- Enter goes to the next question, or to a confirmation screen showing every answer, even when the input holds text.
- Design and experience are still to be refined with the owner.

## Still owed

- The tool's schema (questions, choices, single or multiple, whether a note is allowed) and the result the model gets back.
- How it behaves while a turn runs, in a job lane (0062), and on resume.
- Compare with other harnesses' question tools.

## Proposed design (2026-10-30), for the owner to answer point by point

Built on the approval section (0116, 0157): the same checkboxes, spacing, keys and place above the input.

- **Q1. Name and schema.** A tool `question` (not Claude Code's `AskUserQuestion`), with `questions`: 1 to 4, each
  `{question, header, choices, multiple, note}`: `header` a tab label of at most 12 characters; `choices` 0 to 8 of `{label, description?}`
  (none: the note is the whole answer); `multiple` false by default; `note` one of `"optional"` (default), `"required"`, `"none"`.
- **Q2. The note is the input.** While a question is open, what you type in the input is that question's note, kept per question; Enter
  moves on whatever the input holds, as your sketch says.
- **Q3. Keys.** Up and Down move, Space checks (toggles when `multiple`), a number checks its row, Tab and Shift+Tab go to the next and
  previous question, Enter goes to the next one and after the last to a confirmation listing every answer; Enter there sends, Esc goes
  back. Esc on a question declines the whole series. A click checks a row or opens a tab.
- **Q4. One question, no tabs.** Tabs (`[1 Scope] [2 Tests] [✓ Review]`) appear only for a series.
- **Q5. What the model gets.** One line per question: `Scope: chose "Only the parser"; note: "keep the API"`. When declined: "The user
  declined to answer; continue with your own judgement and say what you assumed."
- **Q6. Where it is not offered.** Not in `ask -p` (no one to answer, and it saves the definition's tokens); never asks for approval
  itself.
- **Q7. While a lane is shown** it leads the status line and waits, as an approval does (ADR-0112); **on resume** an unanswered question
  is recorded as interrupted, as any unfinished call is.

First slice once answered: Q1 to Q3 for one question; then the series with tabs and the confirmation.

## Owner's answer (2026-10-30)

"Everything presented is right, go ahead": Q1 to Q7 as proposed.
