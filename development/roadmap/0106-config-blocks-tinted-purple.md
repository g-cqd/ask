---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0106 — Blocks about ask itself and its configuration, tinted purple

Owner wish (2026-10-28 17:34): ask/config related blocks should be tinted purple; details to be asked.

## Today

`ScreenTheme.tint(for:)` tints the user's messages and tool calls (pending, success, failure) with fixed RGB backgrounds for dark and light
terminals; everything else, including notices, has the terminal's own background.

## Questions for the owner

- Which blocks: the configuration-reload lines ("compactAt: 75% → 0 (file)"), the `/config` editor's output, notices about the sandbox,
  the model or provider switch, MCP and skills loading, sign-in? Or every notice ask writes about itself, as opposed to the model's work?
- A background tint like the tool blocks (a dark violet near `rgb(46, 38, 60)`, and a light one), or purple text on the page's background?
- On a terminal without true colour, the nearest 256-colour entry, or no tint?
- Whether `ui.tint: off` turns it off with the rest (proposed: yes).

## Plan, once answered

A transcript kind for ask's own messages (split from `.notice`), a `system` colour pair in `ScreenTheme`, and a width/colour test like the
other tints.

## Owner's note (2026-10-28)

I was meant to ask refining questions before building (the wish said so) and had only listed them as pending. They are asked in the
conversation of 2026-10-28 and answered here before any work: which blocks count as "about ask or its configuration" (the `/config`
output, `ask config`, reload notices, notices of ask's own actions?); whether the whole block is tinted or only its label; how purple
relates to the yellow of the debug mode (0107); whether errors from ask stay red.
