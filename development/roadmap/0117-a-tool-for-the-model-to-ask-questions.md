---
status: done
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

## Built (2026-10-30)

Q1 to Q7, keys and drawing: the `question` tool (`QuestionTool`, `PersonQuestion`, `PersonAnswer`) validates the questions (1 to 4,
headers of 1 to 12 characters, up to 8 choices, a label each, the note's three words) and refuses a malformed one with what is wrong;
answers come back one line per question (`Scope: chose "Everything"; note: "keep it"`), and a refusal says the user declined. The
screen (`ScreenQuestion`, `PendingQuestions`, `ScreenController+Questions`, `ScreenComposer+Questions`) draws it in the approval
section's place: tabs for a series only, the question in bold, a box per choice with its meaning dimmed, a row of the keys. Up and Down
move; Space or a number checks while the note is empty (after that they type); what is typed in the input is the question's note, kept
per question; Tab and Shift+Tab move; Enter goes on, and after the last of a series to a review that Enter sends and Esc leaves; Esc on a
question declines; Ctrl+C declines and stops the turn; a required note holds Enter. The draft in the input comes back afterwards, also
when the run ends while they wait. In a lane, the status line leads with the question and Esc returns to it. Not offered in `ask -p`; it
never asks for approval. The block's header shows the first question and how many more. Tests: `QuestionToolTests`,
`QuestionSectionTests`, a `ToolSummaryTests` case; interactive probe section Q1 (6 checks).

Two choices of mine, to confirm: a single question sends on Enter, without a review (the review of one answer repeats the screen); and
Space checks only while the note is empty, since the note is typed in the same input.

## Clicks and a showcase scene (2026-10-30)

A click on a choice checks it (whatever the note holds), a click on a tab shows that question, and on "✓ Review" the review; the
section reuses the approval's click regions, since only one of them is ever shown. Tests: `QuestionClickTests`, red first. The showcase
has scene 9, checked in the emulator (shown, clicked, answered). Not yet seen in a real terminal: the owner's run of scene 9 would
close that.


## Owner (2026-10-31): the redesign of the question lane

- **The note moves into the question.** It is an input row right after the last choice, not the usual input below. It takes
  typing only when focused, and wraps at the terminal's width, indented with the choices.
- **Tab moves the focus** between the question tabs, the choices and the note row.
- **The keys inside a question:**
  - arrows highlight a choice;
  - Space selects it;
  - on the note row, typing works as in the normal input.
- **Tab titles lose their numbers.** They were misleading next to the question count.
- **Markers:** `[ ]` for a multiple-choice question, `( )` for a single choice.
- Still open: whether a single question sends on Enter without a review. That stays as built until the owner says otherwise.

## Built (2026-10-31): the redesign

- **The note is a row of the question**, after its last choice: `Note`, under the choices' marks, then what is typed, wrapped at the
  screen's width and indented to the text (`ScreenComposer+QuestionNote`). Each question has its own editor (`PromptEditor`), with
  the input's editing keys. Focused, the row is drawn in the accent colour with an inverse-cell cursor. Empty and not focused, it
  says dimly whether a note is optional or needed. **The input below keeps its draft and takes no key** while the questions wait.
- **Focus** (`PendingQuestions.Focus`): the tabs (a series only), the choices, the note. Tab and Shift+Tab cycle them.
  - On the tabs, Left and Right change question (Right after the last opens the review) and Down goes to the choices.
  - On the choices, Up and Down highlight. Up past the first reaches the tabs, Down past the last reaches the note. Space or a
    number selects.
  - On the note, keys edit. Up from its first row goes back to the choices.
  - A question opens on its choices, or on its note when it has none. A required note held by Enter moves the focus to the note.
  - A click on a choice checks it, a click on the note row focuses it, and a click on a tab opens it.
- **Tabs have no numbers** (`[Scope]   Tests    ✓ Review`), and the tab shown is in the accent colour while the tabs have the focus.
- **Marks:** `( )` and `(•)` for one choice, `[ ]` and `[✓]` for several. The highlighted choice's `›` shows only while the
  choices have the focus. The keys row follows the focus.
- Unchanged, as the owner left it: a single question sends on Enter without a review.
- Tests:
  - `QuestionSectionTests` was rewritten to the redesign: 12 tests, among them the focus cycle, typing only into a focused note, the
    marks, the unnumbered tabs, the wrapped note, and the draft kept.
  - `QuestionClickTests` gained the note click.
  - The new tests did not compile against the old types, which is where they were red.
- Docs: `screen.md`. Probe section Q1 now types its note after Tab and goes on with Enter. Showcase scene 9 is relabelled.
- Not seen in a real terminal.
