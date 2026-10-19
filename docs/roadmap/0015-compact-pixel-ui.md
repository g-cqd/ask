---
status: not-started
blocked-by: ["0003"]
date: 2026-10-18
decision: ADR-0008
---

# 0015 — Two first-class layouts: compact pixel, and compact character

The point of the pixel work: **as much room as possible for content**. Every structural element that
costs a cell should cost pixels instead.

**Both layouts are designed and maintained as first-class** (ADR-0008), not one layout with decoration
applied where possible. A cell layout with pixel decoration would cap compactness at the cell grid, which
is the thing pixels exist to escape.

## What pixels buy, concretely

| Element | Character cost | Pixel cost |
|---|---|---|
| Horizontal rule between panes | a whole row of `─` | `.line`, 1px, no row |
| Vertical gutter rule | a column of `│` | `.line`, 1px, no column |
| Pane or selection background | no cells — background colour | `.fill`, no cells |
| Scrollbar thumb at 40% | 1 character (`█`, `▓`, `░`…) | `.bar` at an exact pixel offset, **no column** |
| Header band | a row of spaces/backgrounds | `.fill` across the row |

Only the last row genuinely diverges. `.fill` and `.line` are decorative and a character layout can
approximate both; `.bar` has **no cell-grid equivalent**, which is precisely why the layouts cannot be
one layout with refinement.

## The fallback is a real audience

Pixel chrome is **kitty-graphics-protocol only** — kitty, ghostty, wezterm, konsole.

Probed what is actually installed: kitty, ghostty and wezterm speak it. **Terminal.app, at
`/System/Applications/Utilities/Terminal.app`, ships with macOS and is therefore on every machine**,
along with Orion RC. The character layout cannot be deferred.

## Parity contract

Two layouts drift unless something forbids it, so the contract is explicit (ADR-0008):

- **Identical:** information architecture, ordering, what is visible, every action and key binding,
  reading order.
- **Free to differ:** how structure is drawn, spacing, density, colour, the scroll thumb.

The test: would a user have to *learn* something new? If yes it belongs in the shared contract. If no,
it is presentation.

## Ordering

After `0013` (chrome lives in the renderer) and after `0003` (measured capability selects the layout —
so a wrong answer shows the wrong interface, not a missing decoration) and after `0014`'s numbers.

## Done when

- Both layouts render the same scenario and pass a parity test over the shared contract, so neither can
  drift from the other silently.
- Neither looks broken: the character layout is its own design, not the pixel layout failing to render.
- The content area is **measurably** larger in the pixel layout than in the character one — measured,
  not asserted.
- The character layout's own density budget is decided and written down: how compact it can be before it
  stops being legible. Undecided at the time of writing.

## What a prototype showed (2026-10-20)

`docs/prototypes/ui-lab/lab.py` is a throwaway screen, fixture data only, tried in kitty. It is evidence for the table
above and for the decisions below. It is **not** a result for the two layouts as built: nothing ran inside ask or
TerminalKit, and no terminal other than kitty was tried.

**Measured or observed**

- **Cell size comes from the ioctl**, as 0014 says: kitty reported 1952 x 1260 px for 122 x 42 cells, so 16 x 30 px.
- **The table holds.** A 1 px hairline and a pixel-positioned scrollbar thumb cost **no row and no column** (checked by
  zooming a screenshot). With glyph separators each costs a row: the bottom stack is **4 / 3 / 2 rows** with pixel
  lines and **5 / 4 / 3** with glyph rules, for the roomy / tight / flush densities below.
- **Padding is inside a block's own surface**, not a margin between blocks. A message, an agent group and a diff each
  open and close with one padded row in their own background, and the gap between blocks is zero. Two surfaced blocks
  that touch would merge into one panel, so in pixel mode a hairline at the top edge of the second separates them for
  free. The character layout has no equivalent and needs another answer, or the blocks must not touch.
- **The bottom section can be nearly flat.** Roomy is a work strip, a two-row input, a status bar. Tight drops the strip
  (its counts are already in the status bar). Flush is a one-row input with its chips inline, then the status bar.
- **Kitty turns the mouse wheel into Up and Down keys** in the alternate screen unless mouse reporting is enabled, so
  an input with a picker is driven by the wheel. ask must enable reporting and handle the wheel (also in 0048).

**Terminal colours first**

- Read the terminal's own background, foreground and ANSI colours (OSC 10, 11 and 4, with a DA1 reply as the end
  marker), derive every surface and accent from them, and fall back to a dark preset when the terminal does not
  answer. Only kitty was tested. wezterm, ghostty and Terminal.app are **unverified**, as is the colour-scheme
  notification (`CSI ? 2031`), which the prototype parses but has not seen sent.
- A contrast guard keeps text readable on any palette: 120 palettes, including Solarized (whose own foreground is
  low-contrast), meet WCAG-style ratios for text, muted text, accents and tinted rows. With the guard disabled the
  check fails at once, so it is not vacuous.
- **Transparent terminals.** Using the terminal's default background keeps its opacity and blur, but surfaces are
  opaque, so on a translucent terminal (the owner's kitty has `background_opacity 0.85`) they look **darker than the
  page**. Painting the base fixes that, but kitty treats an explicit background equal to the default as the default,
  so a painted base must differ by one unit. Both modes need to exist, as a setting.

**Settings worth keeping** (proposed, not decided; they would join the configuration of roadmap 0039): theme source
(`terminal`, `light`, `dark`), accent (an ANSI colour), surface strength, background (`terminal default` or
`painted`), separator style, pixel thickness, transcript spacing, bottom density, status style, layout.

**Still undecided**

- Which of the three bottom densities is the default.
- What separates two touching blocks in the character layout.
- Whether `terminal` is the right default theme source on a terminal that does not answer the colour query.
