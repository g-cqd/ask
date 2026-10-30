---
status: done
blocked-by: []
date: 2026-10-30
---

# 0160 — `/tree` lays out the whole session and blocks the input for seconds

Owner wish (2026-10-30 14:43): "tree command relays out the whole session and user needs to wait seconds to be able to input
anything".

Going back to before a prompt rebuilds the transcript, and the rebuild lays out every block before the next key is read. To do, red first:
time `/tree N` on a long session; lay out only what is on screen and what scrolling reaches (as 0158 needs), and keep reading keys while it
happens. Shares its cause with 0158.

## Done (2026-10-30)

`Scripts/measure-rewind.py`: after `/rewind 170` on the same session the screen drew for 6.2 to 11.4 s (3 s on an older build; 1.4 to
1.7 s for `/rewind 90`). The cause was not layout: the rebuilt history reached the screen as one update per item, and each one drew a
frame that took a copy of the state, so the next item copied the whole transcript again. The conversation now sends the rebuild as one
`ConversationUpdate.batch`, applied in order and drawn once; `/resume` inside ask does the same. `/rewind 170`: 300 to 400 ms; `/rewind
90`: about 190 ms; keys after it under 1 ms. Tests: `BatchUpdateTests`; `probe-tree.py` updated for the `/rewind` name.

Still above the 8 ms action budget: those 300 to 400 ms are reading the session's branch back into updates and applying them once;
worth a profile if it is felt.
