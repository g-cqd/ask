---
status: done
blocked-by: []
date: 2026-11-10
---

# 0217 — Word wrapping in the input

The owner, note n57 (2026-11-09, t249): pretty wrapping was not applied to the input box. InputLayout hard-wrapped every draft.

## The plan

1. Add an opt-in word-wrap mode to TerminalKit's source/caret map, preserving whitespace and hard newlines. Long words still split.
2. Use that mode in both ask's painted prompt and vertical navigation, so clicks, selection and Up/Down cannot disagree.
3. Test actual copy across soft breaks, word boundaries, resizing, narrow widths and wide/combined graphemes.
4. Measure the added layout cost and update the user guide.

## Done when

The word-wrap regressions fail on the former layout and pass on the pinned dependency; the release quality gate passes and CI runs mutation testing. Copy and send preserve the original draft. Real-terminal appearance remains separately unverified until the owner's check.

## Verification

Pinned-dependency release/quality passed (3,773 tests). TerminalKit b692bf8 adds the layout, tested red first, and ask adopted it
in 110a83b4. The click-and-copy regression spans a soft row break; resize and vertical-navigation checks use the same source map.
Mutation testing is left to CI, per the owner's instruction; no local mutation result is claimed. The owner's real-terminal
appearance check remains deferred and is not claimed by these headless tests.
