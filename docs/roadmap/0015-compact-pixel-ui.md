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
- **One block model, for every block, with no leading decoration.** Yours, the assistant's output, thinking, tool calls
  (and the agent group and diff inside them) and the input are all blocks: the same padding above and below, text inset by
  two columns, and nothing at the start of a line. The first versions had a painted bar at the left of each block and
  icons (`▸`, `◆`, `›`, `↪`); the owner was not convinced by either, and asked that **spacing carry the hierarchy**.
  What carries it now: your messages are bold; thinking is faint italic; tool calls are muted with the agent names bold;
  output is plain; the expand hint is text at the right edge (`ctrl+t to expand`), not an arrow at the left; routing to
  another session is words (`to render-review`) and a warning-coloured chip, not a glyph. A test fails if any of
  `▌ ▏ ▸ ▾ ◆ › ↪ ⠹` appears in the transcript, the input or a picker.
- **Unpainted by default.** With surfaces off (the default) the only backgrounds are the terminal's own default and the
  diff's red and green, which are meaning. Chips, the work strip, the status chips and picker selections lose their fills
  and become coloured text. The terminal's opacity, blur and wallpaper are untouched. Surfaces can be turned back on, and
  then each kind of block has its own tint (yours leans to the accent, thinking magenta, tool calls cyan, output neutral),
  capped so the best possible text keeps 7.5:1 (a yellow accent once made a tint so bright that white text failed).
  A test asserts the set of backgrounds in the emitted escape codes; four controls fail it (surfaces on by default, chips
  painting, a leading icon, and a leak found by the test itself: backgrounds that equal the page colour were being painted
  as a one-unit-nudged colour, which would have turned transparency off in the very mode meant to keep it).
- **Padding is not free, and the lab measured it.** In a transcript of mostly one-line blocks (collapsed thinking and
  tool calls), real content rows visible at 120 x 42:

  | Padding | Content rows visible |
  |---|---|
  | none | 38 of 38 (100%) |
  | **half row, shared with the neighbour** | **22 of 36 (61%)** |
  | one full row | 17 of 36 (47%) |
  | aerial (one row, block-line rows, roomy bottom) | 14 of 33 (42%) |

  A half row is drawn with half-block glyphs (`▀` over `▄`) in one boundary row that holds the bottom half-pad of the
  block above and the top half-pad of the block below, so a one-line block costs two rows, not three. It needs no pixel
  support, so it also works where compact cannot use hairlines. Margins and blank rows between blocks were tried and
  removed: they spend content space on nothing (a *breathing room* setting and a *side margin* setting are gone).
- **Separation is the only thing that varies by density.** Compact separates blocks with a 1 px hairline exactly where
  two tints meet (no row). Aerial separates them with a block-line row (`▁`), which costs a row. Neither uses a margin.
  The character layout has no hairline, so its answer is the aerial one or no separator at all, which 0015 still has to
  choose.
- **The owner's settled setup, and what was rejected.** Compact (half-row padding, flush bottom) was tried and the owner
  rejected it ("the compact density is shit"). The setup they chose, from the settings panel, is the `pixel` preset: surfaces
  off, the terminal's own background, 1 px pixel hairlines between blocks, subtle strokes, **one row** of padding, a roomy
  bottom (work strip, input, status), chips, the Surfaces layout. It costs content space (47% of the rows in the lab's
  transcript, against 61% for half rows), and they chose it anyway. Half-row padding and the flush and tight bottoms remain
  as settings, but belong to no preset. The other preset, `aerial`, is the same with a block-line row between blocks instead
  of a hairline. Presets are values over individual settings, and changing one makes the preset `custom`.
- **Strokes must not show through a popup.** Hairlines and the scrollbar are images above the text layer, so ones behind an
  open popup were drawn across it; the owner's screenshot of the settings panel showed lines through its rows. Placements
  inside a popup are now skipped and a tall one is cropped. A test searches every popup, layout and padding for a stroke
  overlapping it, and a control (clipping disabled) fails it.
- **A boundary has one stroke.** With a sidebar, the divider *is* the scrollbar track and the thumb rides on it. Two
  adjacent strokes read as a double border (the first Workbench drawing had exactly that), and a test now fails on it.
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

**Settings worth keeping** (proposed, not decided; they would join the configuration of roadmap 0039): density
(`compact`, `aerial`, `custom`), theme source (`terminal`, `light`, `dark`), accent (an ANSI colour), surface strength (off by default),
background (`terminal default` or `painted`, which matters only with surfaces on), separator style, pixel thickness, stroke visibility, block padding (none,
half row, one row, two rows), bottom section, status style, layout.

**Still undecided**

- Which density is the default, and which bottom section each one gets.
- What separates two touching blocks in the character layout.
- Whether `terminal` is the right default theme source on a terminal that does not answer the colour query.
