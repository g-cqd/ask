---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0160 — `/tree` lays out the whole session and blocks the input for seconds

Owner wish (2026-10-30 14:43): "tree command relays out the whole session and user needs to wait seconds to be able to input
anything".

Going back to before a prompt rebuilds the transcript, and the rebuild lays out every block before the next key is read. To do, red first:
time `/tree N` on a long session; lay out only what is on screen and what scrolling reaches (as 0158 needs), and keep reading keys while it
happens. Shares its cause with 0158.
