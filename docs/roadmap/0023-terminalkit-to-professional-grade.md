---
status: in-progress
blocked-by:
date: 2026-10-19
---

# 0023 — TerminalKit to professional grade, in the order ask needs it

TerminalKit's own roadmap (0006–0014, in that repository) holds the work, each entry with its evidence.
ask's first full-screen use measured TerminalKit under a real app:
- 40-byte cells;
- about 16 ns to rewrite an unchanged cell;
- a one-cell flush at 3 µs (120×40) but 15 µs (300×80);
- 494–1,048 bytes per streamed line.

From the code: input holds a cooperative pool thread, and nothing owns terminal modes.

## Order, by what ask feels

| | TerminalKit entry | Reason |
|---|---|---|
| 1 | **0006**, time benchmarks | Every other change needs a before and an after. |
| 2 | **0010**, modes as a unit | ask already shipped one mode bug (bracketed paste, fixed in ask). Kitty keyboard flags remove the Escape heuristic. |
| 3 | **0007**, compact cells | The lever for the idle-memory budget, and for every frame's per-cell cost. |
| 4 | **0011**, scroll regions | A streamed line currently rewrites every visible row: 186 µs at 120×40 and 354 µs at 300×80 after ask's own composer work. |
| 5 | **0008**, flush proportional to change; **0009**, input on a dedicated thread | |
| 6 | **0012**, text layout promoted from ask's `TextWrap`; **0013**, Unicode widths; **0014**, pipeline isolation | |

## ask's side

ask adopts each entry as it lands, re-pins TerminalKit, and re-runs:
- `Benchmarks/PipelineProbe`;
- `measure-budgets.py`;
- `probe-interactive.py`.

ask's own composer already does work proportional to the change: a keystroke frame went from 172 µs to
42 µs at 120×40, and from 671 µs to 59 µs at 300×80.

## Progress (2026-10-19)

TerminalKit landed 0006 (time benchmarks), 0010 (modes as a unit) and its 0015 (rst's reset techniques), at
`adfd404`. ask pins it:
- `TerminalSession(modes: .fullScreen, keyboardProtocol: .probe)` replaces `StartupSequence`,
  `TerminalTeardown` and the raw-mode calls, and `SignalShutdown` leaves the session;
- the screen hands input to `session.observe(_:)`, which pushes kitty disambiguation when the terminal
  answers, so Escape stops depending on where a read ends;
- leaving raw mode no longer waits on output, so a stopped terminal cannot hang ask's exit.

**0007**, compact cells, pinned at `332ae7a`: two 120×40 grids take 160 KB of live heap, down from
385 KB, and an unchanged cell compares in about 2.3 ns, down from 14 (diary 12).

**0011**, scroll regions, pinned at `2450544`: the transcript is the pipeline's scroll region, and a streamed
line costs 101 bytes instead of 481 at 120×40, and 102 instead of 1,035 at 300×80 (diary 14).

**0008** and **0009**, pinned at `f067f50`: a one-cell flush costs under 1 µs at every size, and input is read
on its own thread, off the cooperative pool (diary 17).

**0012** and **0013**, pinned at `43c4879`: wrapping and the layout cache live in TerminalKit, a streamed line's
layout and flush take a third less (154 → 107 µs at 120×40), and widths match four real terminals, with a cursor
move after the graphemes they disagree on (diary 19).

Next: **0014**, the pipeline's isolation.
