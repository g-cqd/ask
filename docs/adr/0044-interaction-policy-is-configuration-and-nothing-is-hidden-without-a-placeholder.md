---
status: accepted
date: 2026-10-20
---

# 0044 — Interaction policy is configuration, and nothing is hidden without a placeholder

## Context

The owner asked for selection that copies, clicks on components, folding of images and long code, and a bounded input, and said
that TerminalKit provides the mechanisms and ask's settings decide when they apply (TerminalKit ADR-0027). The prototype of
ask's screen has none of it, and ask's screen has no mouse handling, no clipboard code and no disclosure today (checked in the
source, diary 40). The prompt's row limit is a constant, `maximumPromptRows`, in `ScreenComposer`.

## Decision

1. **The policy is configuration.** Whether the mouse is used, whether a selection is copied on release, what starts folded, what
   is shown, and how many rows the input may take are keys in the layered configuration (ADR-0032), so they have a source, can be
   set per project once trusted, and are shown by `ask config`. They are proposed under `ui.*` in roadmap 0051.
2. **The mechanisms are TerminalKit's** (TerminalKit roadmap 0016 to 0019). ask supplies the content and the placeholders, and
   registers what a click means.
3. **Nothing is hidden without a placeholder.** Whatever ask folds, an image, a long code block, thinking, a tool's output,
   leaves a short line of text in its place and can be unfolded. No setting removes the placeholder; a setting can only choose
   between showing the content, the placeholder, and (for images only) drawing nothing where the terminal cannot.
4. **A selection is of content.** ask gives the kit the text of what it drew, block by block, so a selection names a block and a
   position and survives scrolling, and a copy contains the text and not the padding, separators or hints around it.
5. **The terminal's own selection can be given back.** A setting turns mouse reporting off, which returns the terminal's native
   selection and scrollback behaviour, because taking the mouse costs it (TerminalKit ADR-0027).
6. **Copy on release defaults to on.** That is the owner's stated expectation ("a selection of a text should copy automatically"),
   and it is tunable. Every other default is open and is recorded in roadmap 0051 as a proposal, not a decision.

## Consequences

- Roadmap 0051 must settle the defaults, the key names and what each component does before the screen is built around them.
- The screen's layouts (roadmap 0015) must provide the same clickable regions in the pixel and the character layout: a click is
  part of the interaction contract, not of the decoration.
- Session records may need to carry fold state, which is a change to the closed `SessionPayload` enum that roadmap 0027 warned
  about. Whether fold state is persisted at all is an open question in 0051.

## What this does not decide

Which components are clickable, what each does, whether every click has a key, the key names and defaults other than copy on
release, hover, and anything about how the kit draws a selection. Those are roadmap 0051 and TerminalKit 0016 to 0019.

## Update (2026-10-20)

The defaults this ADR left open are decided in ADR-0046, from a probe of four terminals (TerminalKit ADR-0028) and a count of code
blocks, prompts and images in local agent sessions (`docs/research/ui-content-sizes-2026-10.md`).
