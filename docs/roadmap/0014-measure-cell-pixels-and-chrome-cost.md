---
status: in-progress
blocked-by: ["0013"]
date: 2026-10-18
prerequisites: ["ADR-0005"]
---

# 0014 — Measure cell pixels and the cost of chrome before designing a pixel UI

Terminals can render pixels, not only characters, and TerminalKit can already draw with them. Before
any compact UI is designed on that basis, three things have to be numbers rather than assumptions:
what a real terminal reports for its cell size, whether that is enough to draw chrome at all, and what
the chrome costs the four budgets.

## What already exists, and is unused

Probed by reading the source, not the roadmap:

- **`PixelChrome`** (`TerminalKitRender/PixelChrome.swift`) is implemented and byte-tested. It has
  **three** primitives, not one: `.line` (a 1px rule under the cells), `.fill` (a cell-aligned area
  tinted by a 1×1 image scaled to it), and `.bar` (a `widthPixels × heightPixels` rect placed at a
  pixel offset inside its cell).
- **`RenderPipeline.chrome` / `.chromeElements`** — `PixelChrome.render` is called inside `flush()`,
  between the cell diff and the cursor move. It is already on the hot path.
- **`TerminalSize.pixelWidth` / `.pixelHeight`** come straight from `ioctl(TIOCGWINSZ)`.
- Ten byte-exact tests in `Tests/TerminalKitRenderTests/PixelChromeTests.swift`.

**None of it is used by `ask`.** `AskTUI.swift:41` calls `connection.getSize()` and discards the
result with `_ =`, discarding the pixel dimensions along with the columns and rows.

`.bar` is the primitive that matters most for compactness: a scrollbar thumb at 40% is normally one of
four characters, and with `.bar` it is one placement at an exact pixel offset costing **zero columns**.

## What is blocking it

1. **Capability detection is env-var guesswork** (`KITTY_WINDOW_ID`, `TERM_PROGRAM`, `TERM`) — ask
   roadmap `0003`, not started. Worse, it is *insufficient*: `supportsPixelChrome` requires
   `supportsKittyGraphics && cellPixelSize != nil`, and **no environment variable carries a cell
   size**. It can only come from the ioctl. So this entry's measurement is a prerequisite for `0003`,
   not a consequence of it.
2. **`ask` has no renderer.** It has a `ContiguousArray<UInt8>` and a `switch` over bytes. Chrome
   lives inside `RenderPipeline`, which `ask` does not use.

## What was being measured

Run inside real terminals, each launched as `-e /bin/sh -c` so no shell configuration contributes, and
with the detection variables unset in the launcher's own process so each terminal reports its own values:

1. What does `TIOCGWINSZ` report for `pixelWidth`/`pixelHeight` per terminal — real numbers, or zeros?
2. What cell size does that imply, and is it inside `CellPixelSize.drawableWidths/Heights`?
3. What do the four budgets read with chrome enabled versus off, at idle and while repainting?

Scripts are at `Scripts/verify-cell-pixels.py` and `Scripts/verify-chrome-cost.sh`, following
TerminalKit's existing `Scripts/verify-*` split: the in-terminal probe writes only to a file, and the
outside reader is the only thing that inspects results.

A terminal reporting `pixelWidth == 0` gets **no chrome and no error**. That silent degradation is
exactly the failure the white paper warns about, so the probe records zeros as a first-class result
rather than as a skip.

## Measured — items 1 and 2

Run 2026-10-18 across four terminals, each launched as `-e /bin/sh -c` with the detection variables
unset in the launcher's own process, so each terminal reports **its own** values rather than the agent
session's inherited ones.

| Terminal | px W×H | rows×cols | Cell | `KITTY_WINDOW_ID` | `TERM` | `TERM_PROGRAM` | guess | pixels |
|---|---|---|---|---|---|---|---|---|
| kitty | 1274×800 | 32×91 | **14×25** | 1 | `xterm-kitty` | — | True | True |
| ghostty | 1592×1192 | 35×99 | **16×34** | — | `xterm-ghostty` | `ghostty` | True | True |
| wezterm | 560×384 | 24×80 | **7×16** | — | `xterm-256color` | `WezTerm` | True | True |
| Terminal.app | 560×336 | 24×80 | **7×14** | — | — | — | **False** | **True** |

Every cell size is inside TerminalKit's drawable ranges (1…256 wide, 1…512 high).

**Two findings, and they are the whole entry.**

**1. Cell pixels are available everywhere — including Terminal.app.** So pixels are *not* the axis that
separates terminals. What Terminal.app lacks is the kitty graphics **protocol**, and the two are
independent. ADR-0008 had merged them; the measurement separates them.

**2. The first run reported Terminal.app as `guess=True`, and that was contamination.** The agent session
runs inside kitty, so `KITTY_WINDOW_ID=4` was set in its environment and inherited by every terminal the
launcher started. TerminalKit's check is `KITTY_WINDOW_ID != nil || …`, so one inherited variable flipped
a terminal that cannot speak the protocol to "graphics". Scrubbing the launcher's own detection variables
— and letting each terminal set its own — makes Terminal.app read `False`, which is correct.

`env -i` was tried first and is the **wrong** scrub: it strips the environment each terminal sets for its
children along with the inherited one, so all four reported `guess=False` including kitty. That is a
different wrong answer, and a more dangerous one, because it makes detection look broken everywhere
rather than contaminated in one place.

Cell height varies by **2.4×** across these terminals (14 px to 34 px), which matters for any density
budget: a compact layout tuned at one cell size is not the same layout at another.

## Still owed — item 3

What the four budgets do with chrome enabled versus off cannot be measured yet, because `ask` has no
renderer and no chrome to enable. That is `0013`'s work, and this entry stays `in-progress` until then.

Reproduce with `OUT=/tmp/ask-cell bash Scripts/verify-chrome-cost.sh`.

## Cost, stated as what is known and what is not

Known by reading `PixelChrome.render`: a steady-state frame is close to free — it early-returns when
`placed == elements`, images transmit **once** and are thereafter re-placed rather than re-sent, and
every command is `isQuiet: true` so nothing returns on the input stream. A repaint costs placements,
not payloads.

Not measured, and therefore not to be assumed: the memory and byte cost against the 8 MiB idle budget.
A 1px rule transmits `4 × length` bytes of RGBA once (400 bytes for a 100-column rule), then caches.
Small on its face — **small on its face is not a measurement.** Item 3 above settles it.

## Done when

- [x] A table exists, per terminal, of reported pixels, implied cell size, and whether that size is drawable.
- [ ] The four budgets have chrome-off and chrome-on numbers from the same harness and the same run.
- [x] Zeros are recorded as a result, with the terminal named.
- [x] `0003` can be written against measured facts rather than against an assumption about `TERM_PROGRAM`.

## Not in this entry

Designing the compact UI. Laying out borders, gutters or a header band against a capability that has
not been measured is the mistake this repository's own history is a catalogue of — the 3,530-line seam
estimate, the Aemi zero-tags "blocker", and the stale lockfile in `d5099ea` were all design decisions
taken ahead of a probe.

Pixel chrome is **kitty-graphics-protocol only** — kitty, ghostty, wezterm, konsole, per the detection
list. Terminal.app is not in it. So a pixel-first UI needs a character-mode fallback that looks
intentional rather than broken. That doubles the UI surface, and it is a design constraint to settle
before the renderer is adopted, not after.