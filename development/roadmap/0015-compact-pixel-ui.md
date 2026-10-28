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

`development/prototypes/ui-lab/lab.py` is a throwaway screen, fixture data only, tried in kitty. It is evidence for the table
above and for the decisions below. It is **not** a result for the two layouts as built: nothing ran inside ask or
TerminalKit, and no terminal other than kitty was tried.

**Where the owner landed.** These are the owner's decisions, reached by looking at the prototype. Several earlier designs
were built and rejected; they are listed because they would otherwise be tried again.

- **Nothing is painted.** Every background is the terminal's own default, so its opacity, blur and wallpaper are untouched.
  The theme and colour scheme apply to **text and status only**. The prototype emits no background escape code at all, and a
  test fails if one appears. *Tried and rejected:* a tint per kind of block (needed a contrast guard, and its opaque cells
  looked wrong on a translucent terminal), a "painted base" mode, filled chips, filled picker selections, red and green
  diff backgrounds. The diff is red and green **text**.
- **No leading bar, no leading icon.** *Rejected:* a painted bar at the start of each block, and `▸ ◆ › ↪ ⠹ ● ▲ ✓ ○`,
  including in the status bar and the sidebar. Nothing starts a line but its text.
- **Hierarchy is spacing, type and text colour.** Your messages are bold; thinking is faint italic; tool calls are muted
  with the agent names bold; output is plain; the expand hint is text at the right edge (`ctrl+t to expand`); the status bar
  is text, with a warning colour for what needs the user; routing to another session is words (`to render-review`).
- **One block model, with padding of one block row.** Every kind of block (yours, output, thinking, tool calls) and the
  input have one blank row above and below their content, inside the block, and the text is inset two columns. Padding is
  **none or one block**, never more. *Rejected:* half-row padding drawn with half-block glyphs, and two rows. It costs
  content space: in a transcript of mostly one-line blocks, one-row padding leaves **47%** of the screen's rows for content
  (half rows left 61%, none 100%), and the owner chose it anyway.
- **Separators are a pixel line where pixels exist, and a block line elsewhere.** A pixel line (1 or 2 px, kitty graphics)
  costs no row. A block line is an eighth-block glyph row (`▁`) and costs one, which is what a terminal without pixel
  support gets. *Removed:* the `aerial` preset and every preset; the box-drawing and background-only styles.
- **Strokes are quiet and tunable.** One stroke colour for lines, the scrollbar track and the sidebar divider, at three
  levels (`subtle` by default, `normal`, `strong`), plus a thickness (1 or 2 px). Subtle keeps at least 1.4:1 against the
  terminal's background and is never as loud as text.
- **Two layouts: standard and workbench.** *Flat* and *surfaces* were merged at the owner's decision. With nothing painted,
  "surfaces" was only "flat plus a separator between blocks", so there is one single-column layout, with the spacing and the
  separators, and *workbench*, which is that plus a sidebar of tasks, agents and context. The sidebar changes the width and
  never the spacing, and a test fails if it does. Saved settings from the three-layout version migrate: flat and surfaces
  become standard, workbench stays workbench.
- **A roomy bottom by default** (work strip, input, status). *Rejected:* the flush bottom with half-row padding, called
  "compact", which the owner described as bad. Tight and flush remain as settings.

**Measured or observed**

- **Cell size comes from the ioctl**, as 0014 says: kitty reported 1952 x 1260 px for 122 x 42 cells, so 16 x 30 px.
- **The table holds.** A 1 px line and a pixel-positioned scrollbar thumb cost **no row and no column** (checked by zooming
  a screenshot). With block lines each costs a row.
- **A boundary has one stroke.** With a sidebar, the divider *is* the scrollbar track and the thumb rides on it. Two
  adjacent strokes read as a double border, and a test fails on it.
- **Strokes must not show through a popup.** Lines and the scrollbar are images above the text layer, so ones behind an open
  popup were drawn across it, as the owner's screenshot of the settings panel showed. Placements inside a popup are skipped
  and a tall one is cropped; a test covers every popup, layout and padding, and a control (clipping disabled) fails it.
- **Kitty turns the mouse wheel into Up and Down keys** in the alternate screen unless mouse reporting is enabled, so an
  input with a picker is driven by the wheel. ask must enable reporting and handle the wheel (also in 0048).

**Terminal colours first**

- Read the terminal's own background, foreground and ANSI colours (OSC 10, 11 and 4, with a DA1 reply as the end marker)
  and derive the **text** colours and the accent from them. When the terminal does not answer, use plain ANSI colours, which
  adapt to a light or a dark terminal without guessing a palette. Only kitty was tested. wezterm, ghostty and Terminal.app
  are **unverified**, as is the colour-scheme notification (`CSI ? 2031`), which the prototype parses but has not seen sent.
- A contrast guard keeps text readable on any palette: 90 checks (six palettes, including Solarized, whose own foreground
  is low-contrast, times five accents times three stroke levels) for text, muted text, the accent, the status colours and the
  strokes. With the guard disabled the check fails at once, so it is not vacuous.
- **Transparent terminals** stop being a problem by construction: with nothing painted, the owner's kitty
  (`background_opacity 0.85`) shows through everywhere. The earlier mode that painted surfaces looked darker than the page
  and needed a one-unit colour nudge to defeat kitty treating an equal background as the default; it is gone.

**Settings worth keeping** (proposed, not decided; they would join the configuration of roadmap 0039): accent (an ANSI
colour), separators (`pixel line`, `block line`), line thickness, strokes, block padding (`none`, `1 block`), bottom section,
layout (`standard`, `workbench`).

**Still undecided**

- What the character layout does about the row a block line costs, since padding already spends rows.
- Whether bold and italic carry the hierarchy in the fonts the owner's terminals use: nothing tests that they render.
- Clicks, selection and folding: the prototype has none of them. They are roadmap 0051 (the study across the screen) and
  TerminalKit 0016 to 0019 (the mechanisms), and both layouts here must offer the same clickable regions.

## The sidebar, ahead of the pixels (2026-10-24)

The owner wants the runner tree in the workbench sidebar. That is built for the character layout first, as roadmap 0062 step 4, and does not wait for
0014 or 0003; the pixel stroke later replaces only the divider.
