---
status: not-started
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
