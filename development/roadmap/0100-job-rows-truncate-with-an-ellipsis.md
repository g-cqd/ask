---
status: done
blocked-by: []
date: 2026-10-28
---

# 0100 — Job rows under the input end with … when truncated

Owner wish (2026-10-28 16:57): job commands and titles listed below the input end with `…` when cut to the terminal width, and the duration is
separated from the spinner by ` · `. Close to 0080 (tool header ellipsis); share the truncation helper.

## Result (2026-10-28)

- Job rows below the input end with `…` when cut, with or without a clock, through `ScreenComposer.ellipsized`, the helper 0080's
  one-row headers now use as well. The duration and the spinner are joined by ` · `, and the gap before them is the block headers' two cells.
- Tests: `RunnerProgressTests` updated to the new suffix, plus a row with no clock cut at three widths.
