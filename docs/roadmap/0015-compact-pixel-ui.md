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