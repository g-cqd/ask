---
status: done
blocked-by: []
date: 2026-10-28
---

# 0108 — Colours follow the system appearance

Owner wish (2026-10-28 19:10), marked highly critical: colour support should read the current macOS appearance, change when it changes,
and match it by default, so colours and contrast work with the terminal's configuration (for example a terminal in light mode). Verify with
screenshots and printed mocked sessions that show the various blocks and how they look.

## Decisions (owner, 2026-10-28)

- The terminal's theme wins, not the system's: ask reads the terminal's background (OSC 11) and derives its tints from it. The standard
  Apple Terminal is the reference case: its default profiles change their own colours with the system appearance, so ask must follow the
  change while it runs, and re-read the background when the appearance changes.
- The current tints give poor contrast, the owner's words: the background tints are fixed colours picked for a dark page, and Apple Terminal
  sets no `COLORFGBG`, so a light Terminal window gets dark tints. Derived tints replace the fixed tables.
- An override replaces the behaviour completely: a `ui` key fixes the palette, with no query and no following.
- 0109 (AemiHMMML) scope is left for later.

## Result so far (2026-10-28)

- `ui.appearance`: `auto` (default), `light` or `dark`. A fixed value replaces the behaviour completely: no query, no following.
- On auto, ask sends OSC 10 and OSC 11 at start and mixes the tints from the answer (`TerminalColours`, `ScreenTheme(page:)`). The query
  carries no device-attributes request, because the keyboard probe owns that reply. Answers are taken out of the input and never typed.
- Following: the composition root observes `AppleInterfaceThemeChangedNotification` (a system API, no polling) and the screen asks again
  0.15 s and 1.15 s later. The observer lives in the public entry point, not the screen, because registering one per test session hung the
  suite.
- First guess before the answer: `COLORFGBG`, else the macOS appearance (`AppleInterfaceStyle`), because Apple Terminal sets no `COLORFGBG`.
  The old default was "dark", which gave dark tints in a light Terminal window.
- Contrast: tint shares tuned so text on every tint keeps at least 80% of the terminal's own WCAG contrast on Apple Terminal Basic (light
  and dark), Solarized (light and dark) and One Light, while each tint stays visibly off the page.
- Owner follow-up (block text too faint, on light and dark): once the page is known, nothing is drawn faint. Secondary text is a grey
  80% of the way from the page to its text (11:1 to 13:1 on Apple Terminal Basic), or the text colour itself when that grey would read
  below 4.5:1. Coloured text, such as the green status, keeps its colour at full strength. On a guessed page, faint stays: a grey mixed for
  the wrong page could vanish, and the guess lasts until the terminal answers.
- Found on the way: the sandboxed status mark was ANSI white, nearly invisible on a light page. It is now the terminal's text colour, bold.
- Tests: `TerminalColoursTests` (contrast on five profiles, answer parsing, event taking, legibility, no faint cell on a known page),
  config tests for the key. PTY: `Scripts/probe-terminal-colours.py`, 10 checks, the probe answering for the terminal and posting the
  real notification.

## Verified by the owner (2026-10-28)

The owner ran it in Apple Terminal and reports it "perfect"; the real-terminal check below is closed by that.

## Left for later

- A run in the real Apple Terminal, light and dark, with screenshots of a mocked session showing every kind of block. Not done: it opens
  windows on the owner's machine and needs screen recording permission. Unverified until then: that Apple Terminal answers OSC 10 and 11,
  and when its profile colours change relative to the notification.
- Terminals that report changes themselves (DEC mode 2031) could be followed off macOS; not done.

## Open questions

- Over SSH or in tmux, the system appearance belongs to another machine and tmux may not pass OSC 11 through: is the terminal's answer
  enough there, and what should the first guess be?
