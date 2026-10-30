---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0162 — An interrupted block's status says "interrupted"

Owner wish (2026-10-30 14:43): "when a block is manually interrupted the exit code bracketted component in the block status should
include the word "interrupted"".

Today a stopped command's header ends with `⊘` (0142), with the bracketed exit code when there is one. To do: the bracketed part reads
`[interrupted]` (with the code when the process reported one: `[interrupted · 130]`), in the same orange as `⊘`; probes in
`probe-interactive.py` updated.
