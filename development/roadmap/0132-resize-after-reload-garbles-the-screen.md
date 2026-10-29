---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0132 — Bug: a resize after /reload garbles the screen

Owner, marked as a bug (2026-10-28 23:46): after `/reload`, if the terminal changes size, the screen is completely wrong, above all the
input section, where every printed line is garbled.

## To find

`/reload` re-executes ask in the same terminal. Suspects, in order: the signal state a re-executed process inherits (a blocked or ignored
`SIGWINCH` survives `exec`), the terminal modes or the scroll region left by the first process, and the render loop's size at start against
the resize stream. Reproduce first with a PTY probe: start, `/reload` into a second binary, resize, read the screen.
