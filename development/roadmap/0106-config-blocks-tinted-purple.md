---
status: done
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

## Owner's answers (2026-10-29)

1. Which blocks: those about ask itself and its configuration: `/config` and `ask config` output, reload notices, ask's own action
   notices. In practice every notice that is not an error, since a notice is ask speaking.
2. The whole block is tinted purple, as the user's block is blue.
3. Separate from the debug mode: purple is ask's own messages, yellow (0107) is debug.
4. Errors stay red.

Ready to build: a transcript kind for ask's own messages, a `system` tint in `ScreenTheme` that keeps the contrast test, text in the
terminal's foreground.

## Result (2026-10-29)

Built to the owner's four answers. Every notice that is not an error is a purple block: the whole block, padding rows to the edge, tinted
from the page like the others (`ScreenTheme.system`, a 11% mix of purple that keeps at least 87% of each profile's own contrast and sits
15 units of red-over-green away from the user's blue on light, dark and Solarized pages); text in the terminal's foreground. Errors stay red
and untinted; `ui.tint: off` removes it with the rest. Because notices are all ask speaking, no new transcript kind was needed. Like the
user's and the tool blocks, consecutive ones are set apart by a blank row, which made the `/help` block one row taller. Tests:
`SystemBlockTests`, and the contrast test covers the new tint. Real binary: `Scripts/probe-system-block.py`.

