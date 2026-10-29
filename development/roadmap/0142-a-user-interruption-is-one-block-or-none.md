---
status: done
blocked-by: []
date: 2026-10-29
---

# 0142 — A user's interruption is one block, or none and a colour

Owner wish (2026-10-29 13:08): "The following should not be 2 blocks, only one block and i think stopping should be replaced by aborted. but we
could also think about making an interruption by the user not show anything and have the ongoing tool call, block, turn purple or orange instead
of red to signify the difference and not add a stopped or aborted block, just rely on the color"

    > Stopping…
    > Aborted. Results already known were kept.

## Options

1. **One block.** "Stopping…" becomes the status bar's state while the turn winds down (as "Reconnecting…" does, 0120), and the transcript
   gets one block when it has: "Aborted. Results already known were kept."
2. **No block, a colour.** The interrupted tool call, block or turn takes an interruption colour (purple or orange, from the palette, distinct
   from the error red), and nothing is added. The status bar says it was interrupted until the next input.

Either way, the session file records the interruption once (resume and `/tree` show it), and the copy of a block carries no marker.
Owner to choose; 2 needs a colour check on light and dark pages (`ui.appearance`).

## Owner decision (2026-10-29)

No interruption block at all: only the last ongoing blocks turn **orange**. This supersedes both proposed choices above: do not move
"Stopping…" into another transcript block, and do not colour older completed blocks. Preserve known results, distinguish interruption
from failure, and verify contrast on light and dark pages. Implementation is approved, after the urgent Claude investigation (0144).

## Done (2026-10-29)

Stopping a turn adds no block: "Stopping…" and "Aborted. Results already known were kept." are gone. At the stop, the reasoning and the
foreground tools still going (a compaction too, drawn as a tool) end and are drawn on an orange tint mixed from the page like the others,
their status `⊘` in orange (a mark of its own, for anyone who cannot tell the colours apart). A result arriving later is kept, and the
block stays orange unless it succeeded. Older blocks keep their colours; background jobs go on. The orange tint is in `ScreenTheme.tints`,
so `TerminalColoursTests` checks its contrast on light and dark pages. Tests: `InterruptionColourTests` (a mutation that skips the
interruption turns all five red); `probe-interactive.py` B and W through the release binary. Not covered: an assistant reply cut while
streaming has no header to colour, so it simply stops; `probe-agy-live.py` (a live account) was updated but not run.

