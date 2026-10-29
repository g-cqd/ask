---
status: done
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

## Result (2026-10-29)

Not a counting error. The recorded usage in the owner's biggest session (1,930 responses) sums to 1,187,873 output tokens, which is what
the status line counted. The display was the problem: millions had one decimal, so 1.10M through 1.19M all read `1.1M`, and at about 600
output tokens a response that is roughly 160 responses without a visible change. Millions now have two decimals (`1.18M`), and from 10M
none (`12M`); a context window label keeps its one decimal (`1.0M`). The same session shows 311M prompt tokens, of which 304M are cache
reads, so `↑` counts every prompt token sent, cached or not; if the owner wants `↑` to count only new tokens, that is a separate choice.

