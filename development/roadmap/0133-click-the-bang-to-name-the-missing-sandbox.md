---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0133 — Click the ! mark to show that there is no sandbox

Owner wish (2026-10-29 00:00): clicking the first status component `!` (the mark that says ask runs without its sandbox) shows "not
sandboxed" in its place, and after 5 seconds it goes back to `!`.

Notes: the mark is a click target in the status line like the job count; the text is `not sandboxed` with the warning colour; the timer
is the screen's own, not a sleep in a test. When the sandbox is on, the mark is not yellow and a click could say `sandboxed`: ask the
owner whether it should.
