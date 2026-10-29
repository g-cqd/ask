---
status: done
blocked-by: []
date: 2026-10-29
---

# 0132 — Bug: a resize after /reload garbles the screen

Owner, marked as a bug (2026-10-28 23:46): after `/reload`, if the terminal changes size, the screen is completely wrong, above all the
input section, where every printed line is garbled.

## Cause and fix (2026-10-29)

`/reload` ends in `execve`, called from a Swift concurrency worker thread. That thread has `SIGWINCH`, `SIGINT`, `SIGTERM` and most other
signals **blocked** (read in a traced debug build: 1, 2, 3, 6, 14 to 16, 18 to 26 and 28 to 31). `execve` gives the calling thread's mask to
the new program's first thread, and every thread the program creates inherits it, so in a reloaded ask no thread could take `SIGWINCH`:
the handler was installed (the kernel's `p_sigcatch` showed it) and the signal was never delivered to it. A fresh ask has a main thread
with an empty mask, which is why only a reload broke. The terminal reflowed the old frame and ask never drew a new one. Intermittent by
nature: which thread a signal reaches depends on which still allows it, and a probe saw the first resize after a reload handled and the
second not. The same mask also held back `SIGTERM`, so a reloaded ask could not be stopped by `kill`.

Fix: `Reexec.replaceProcess` clears the calling thread's mask before `execve`. Evidence: `Scripts/probe-reload-resize.py` reloads into a
copy of the binary, resizes four times, requires a new frame at the new size each time, and sends `SIGTERM`; it failed on the unfixed
build and passes three runs in a row on the fixed one. Then the owner's own offer, in a real window: kitty with remote control, a
fake provider and an eight-turn session, a reload, and `resize-os-window` through the window system: before the fix the screen was left torn
(no input box, no status line, stale wrapped text); after it three resizes (70x22, 110x34, 60x18) each repainted fully. Kitty and the
provider were closed and their files removed afterwards.

