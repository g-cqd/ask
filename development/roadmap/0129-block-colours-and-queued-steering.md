---
status: done
blocked-by: []
date: 2026-10-28
---

# 0129 — Block colours: running tools grey, the user blue, queued steering without background

Owner wish (2026-10-28 23:11):

- A running tool call is greyish, not bluish.
- The user's input, once it is a block, is blue, bluer than a running tool.
- Text stays clear: white, or the scheme's prominent colour, on light and dark pages alike (0108's derived palette).
- Queued steering is grey and dimmed, without a background, and its "Queued steering:" label is replaced by a spinner and the standard
  separator ` · `.

The tints come from `ScreenTheme` (0108): `pending` mixes toward blue today, `user` toward the foreground with some blue. Swap the
hues, keep the contrast test, and give queued items their own style.

## Result (2026-10-28)

- A tool still running is grey (its tint mixes toward the page's text colour, not blue); the user's block is blue, mixed 12% from blue on
  every page, which tilts it about 22 channel units bluer than the page against about 0 for a running tool (tested on light, dark and
  Solarized). Text keeps the terminal's own foreground, bold for the user, so it is white or black as the page needs. Text on every tint
  still keeps at least 80% of the terminal's contrast on five real profiles.
- Queued steering and follow-ups are a transcript item of their own, `queued`: dim, no background, a spinner then ` · ` then the text, the
  other rows hanging under it, no label. The spinner turns while it waits and becomes `↩` when the text went back to the editor; accepted,
  it is the user's block and its spinner is gone. Steering and follow-up look alike now.
- Tests: `QueuedBlockTests`, and the tests that expected the old notices. The real binary shows the queued lines (probe J).
- Debt found: `Scripts/probe-interactive.py` still expects the pre-0074 `ask> ` prompt and ` · ready`, and pre-0064 Ctrl-C and Esc
  behaviour; those checks fail for reasons unrelated to this change and the probe takes minutes. It needs bringing up to date (0079).

