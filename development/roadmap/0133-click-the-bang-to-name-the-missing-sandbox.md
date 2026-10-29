---
status: done
blocked-by: []
date: 2026-10-29
---

# 0133 — Click the ! mark to show that there is no sandbox

Owner wish (2026-10-29 00:00): clicking the first status component `!` (the mark that says ask runs without its sandbox) shows "not
sandboxed" in its place, and after 5 seconds it goes back to `!`.

Notes: the mark is a click target in the status line like the job count; the text is `not sandboxed` with the warning colour; the timer
is the screen's own, not a sleep in a test. When the sandbox is on, the mark is not yellow and a click could say `sandboxed`: ask the
owner whether it should.

## Owner's design (2026-10-29)

The mark is a state, not only a warning. With the sandbox on, the first status component is a green checkmark `✓`; clicking it expands it
to a green `sandboxed`, which goes back to `✓` after 5 seconds. With the sandbox off it stays `!` in the warning colour and a click
shows `not sandboxed` for 5 seconds. This changes the idle mark everywhere it is read: `StatusLeadingMark`, the probes that look for a
`!` at the start of the status line (`Screen.idle()` in `probe-interactive.py`), and the spinner, which still replaces it while a
turn runs.

## Result (2026-10-29)

Idle, the first status component is a green `✓` with the sandbox on and a warning-coloured `!` with it off; a spinner still replaces it
while a turn, a compaction or a reconnection shows. A click on the mark names the state in the same colour, `sandboxed` or `not
sandboxed`, and five seconds later (one-shot timer by generation, as the quit window) the mark is back; a second click closes it at once, and
a timer from an earlier click means nothing. The mark's columns are a click region only while it is the idle mark. Tests:
`SandboxMarkTests`; the tests that pinned `! ·` for the default state now pin `✓ ·`. Real binary: `Scripts/probe-sandbox-mark.py`
(8 checks, sandboxed and `--no-sandbox`, including the real five seconds); `probe-interactive.py`'s `idle()` accepts the new marks.

Owner (2026-10-29): the words are capitalised, `Sandboxed` and `Not sandboxed`.
