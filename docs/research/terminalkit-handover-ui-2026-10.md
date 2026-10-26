# Handover to TerminalKit: what ask's screen redesign (roadmap 0074) needs from the kit

From the `ask` repository, 2026-10-26. TerminalKit pinned at `554a2248e16ce925f83f5f37ee06855156554079`. **Nothing here is built or probed against the kit yet unless it says so**; the kit's source was read, not exercised, for the items marked "read". The list is ordered by how much the redesign depends on it.

## What ask is about to do (so the asks make sense)

Tinted backgrounds on whole rows (the input; tool-call blocks; by outcome), a one-row separator above the input (pixel line where possible), a status line below the input with a coloured warning glyph, and one-row padding around every block. All of it inside the transcript's scroll region as ADR-0022/kit ADR-0011 set it up. Prior ask decisions were "nothing is painted", so none of this has been tried on the kit.

## 1. Terminal palette and colour-scheme delivery at the session level (probably needs kit work)

Read: `TerminalKitCodecs/OSCPalette.swift` builds the OSC 10/11/4 query closed by `CSI c` and parses replies; `TerminalKitIO/TerminalProbe.swift` has `ProbedCapabilities` (cell pixel size, keyboard protocol flags, synchronized output) but **no palette**, and nothing outside `OSCPalette` references it.
Need: an API on `TerminalSession`, or on the probe, that returns the terminal's foreground, background and ANSI colours at start, and ideally a stream of changes (`CSI ? 2031` colour-scheme notification, `CSI ? 996 n` query) so ask can derive a tint that is "a little darker than the terminal's own background" instead of guessing. Without it ask ships a fixed dark set, a light set from `COLORFGBG`, and `ui.tint = off`.
Questions: does the input router already hand an OSC reply to the app (the doc comment says it hands over an OSC it does not decode)? Is there a safe place for the query while raw mode and the keyboard probe are in flight (the `CSI c` terminator is shared with the keyboard probe's)?

## 2. Background-on-scroll safety (probably nothing to build; needs a probe and a test)

Read: `DiffRenderer` appends an SGR reset at the end of a frame when the last style was not default; the scroll region is driven by `RenderPipeline.scrollRegion` / `scrollHint`.
Why it matters: terminals with back-colour-erase fill the rows a scroll exposes with the *current* SGR background. If any code path scrolls while a tinted style is current, a coloured band appears at the exposed edge.
Ask: a kit test that scrolls a region whose last written cells carry a background and asserts the exposed rows are default-background (emit `ESC[0m` before every scroll sequence, if the test shows it can happen). ask will add its own PTY probe on top.

## 3. Whole-row background fills and the diff (read; likely fine)

`ScreenBuffer.fill(row:col:width:height:cell:)` with a `Cell` carrying only `bg` is what ask now uses for the tail of a tinted row. Please confirm the diff does not treat a blank cell with a background as skippable or "empty" when the previous frame had default (the `Cell.empty` special case), and that `writeGap` (unchanged cells rewritten when cheaper than a cursor move) cannot carry a stale style across a background change.

## 4. Pixel separator in the render pipeline (maybe)

Read: `PixelChrome` and `ChromeLine`/`ChromeElement` exist, with `TerminalCapabilities.supportsPixelChrome`. ask's `ScreenComposer` implements `FrameComposer` with a `RenderPipeline` but does not place chrome.
Ask: the supported way for a `FrameComposer` to place a `ChromeLine` (a 1 px rule between two rows, no row cost) and have it cleared when the layout changes, resize, scroll or a popup covers it (ask's earlier prototype had strokes drawn across a popup). Until then ask draws a box-drawing row, which costs a row (ADR-0008 says the layouts may differ).

## 5. Width of the new glyphs (needs a probe per terminal)

ask will draw `⚠` (U+26A0), `⛨` (U+26E8), `↑` `↓` (U+2191, U+2193), `─`, `▁`. `⚠` has text and emoji presentations and East Asian Ambiguous width for some. Kit ADR-0013 ("Unicode width against real terminals") is the right place: please state what `UnicodeWidth.displayWidth(of:)` returns for each and whether kitty, Terminal.app, ghostty and wezterm agree, with a variation selector (U+FE0E) if that is what makes them agree. A disagreement misplaces every cell to its right on that row.

## 6. Italic + faint, and a style with only a background (read; confirm)

`Style` has `dim` and `italic` and `bg`. Please confirm `SGREncoder` emits `2` (faint) and `3` (italic) together and that a style that differs only in `bg` produces the shortest diff, since padding rows are blanks that differ only by background.

## What ask will do meanwhile

Fixed tint colours with a light/dark guess, `ui.tint` to turn it off, a box-drawing separator, and its own PTY probes for items 2 and 3. Each is replaced when the kit answers.
