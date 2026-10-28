---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0085 — Investigate text wrapping, and markdown colouring in the input

Owner request, from `ask-wishes.md`. This is an investigation: its result is a written finding and a decision,
not a feature. It is related to 0065 (markdown in the transcript, in progress).

## Questions

- Wrapping of prose in the input and in output messages (not code blocks): what the wrap does today
  (`TextWrap.rows`, `FrameGeometry`) and where it looks wrong: breaks inside words, URLs and paths, wide
  characters, indentation of lists and quotes. Collect real examples with the terminal width.
- Whether a better wrap belongs in AemiMarkdown or AemiText (ask does not depend on AemiMarkdown today; check
  `Package.swift`), or in TerminalKit's text module, per roadmap 0076 on where reusable algorithms live.
- Markdown colouring in the input while typing: syntax colour only, the typed characters stay exactly as typed
  (no removal of `*`, `#` or backticks), so the text stays editable.
  - Which element kinds are coloured, and the cost per keystroke on a long paste.
  - How an unfinished construct (a lone `*`, an unclosed fence) is coloured without flicker.
  - Whether the cursor and selection logic in `PromptEditor` are affected, which should not be the case if only
    styles change.

## Deliverable

A short report in `docs/research/`, with measurements and a recommendation for each question, then new roadmap
entries for what the owner accepts.
