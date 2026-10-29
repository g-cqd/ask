---
status: done
blocked-by: []
date: 2026-10-28
---

# 0125 — Scrolling up stops at the first block

Owner, marked as a bug (2026-10-28 22:52): holding fn+Up (Page Up) on a Mac scrolls the conversation past its start into empty
screens. It should stop when the session's first block is at the very top of the screen.

## Result (2026-10-28)

Page Up added a page to `scrollback` with no ceiling, while the wheel went through `scroll(by:)`, which stops at the first line.
Page Up now uses `scroll(by:)`: held down, it stops with the session's first line at the top of the screen. fn+Up on a Mac keyboard is
Page Up. The test that expected an empty conversation to scroll 14 lines encoded the bug; it is replaced by one on 40 lines that holds
Page Up and checks the stop, and both new tests fail with the old line restored.

## Moved to TerminalKit (2026-10-29)

The wheel, the Page keys, edge autoscroll and the fold that holds the reader's place all use `ScrollPosition` (kit roadmap 0021): one place for
"no further than the first row at the top", where there were three. `state.scrollback` remains as a read view of it.
