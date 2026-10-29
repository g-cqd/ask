---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0136 — Bug: the token counts look stuck near 1.1M

Owner, marked as a bug (2026-10-29 00:32): on the biggest session, the output/received token count has been stuck at about 1.1M for
some time.

## To find

Read how `UsageTotals` adds up a response's usage and what `deliver` records: whether a total is capped, whether a resumed session recounts
from the file (and from which entries), whether the status line shows a different quantity than the total (the last request's input
against the sum), and whether a provider that reports usage only at the end of a stream is counted per request or per event. Reproduce
with a scripted provider and a long session, then compare with the session file's own recorded usage.
