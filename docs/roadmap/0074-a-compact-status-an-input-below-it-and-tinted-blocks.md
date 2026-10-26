---
status: in-progress
blocked-by: []
date: 2026-10-26
supersedes-in-part: "0015 (nothing is painted; no leading icon; roomy bottom with the status above the input)"
---

# 0074 — A compact status line below the input, a tinted input, and blocks with padding

The owner's request, 2026-10-26, in their own order, with pi's screen as the model. It **reverses** decisions recorded in roadmap 0015 ("Nothing is painted", "No leading bar, no leading icon", status above the input). Those were the owner's
too, reached by looking at a prototype; this entry is the owner changing their mind after using the real screen, and it is recorded as that so the earlier rejections (a tint per kind of block "needed a contrast guard and looked wrong on a
translucent terminal"; icons) are not rediscovered as surprises. The ADR that closes this entry supersedes those lines of 0015.

## What was asked

**The status line**
1. Adapts to the terminal width: shows complete pieces of information and **never cuts one in the middle**; what does not fit is dropped whole, lowest priority first.
2. More compact: `codex/gpt-6.1-sol/medium` (provider/model/effort), then usage as `↑in ↓out` (arrows, not the words).
3. Says nothing that conveys nothing: no `ready`; sandbox **on** is not shown; a copy sent to the terminal is just copied, no notice (a failure still says so).
4. No sandbox is a warning: a coloured triangle (yellow, orange or red), as a prefix or suffix of the line. Sandbox on: at most a quiet shield mark; "all white for now" is acceptable while the palette is small.
5. **Below the input**, not above it.

**The input**
6. No `ask> ` prefix by default; a `ui.prompt` setting says what to use if anything.
7. Marked instead by a slightly darker, semi-transparent-looking background.
8. Above it, a separator from the conversation: a pixel line where pixels exist, a box-drawing row where not.

**The blocks (pi's model)**
9. Every text block (thinking, tool, command, user, notice) has **one block of padding all around**, whatever its content and whether it is folded or growing.
10. **One empty block between consecutive tool-call blocks.** Model answers and thinking get their padding only, no extra spacing.
11. Tool calls have a tinted background up to behind the padding (border-box), by outcome. **The user's own message, once sent, is tinted too**, like the input it came from (added by the owner after the first list). Answers have no tint. Thinking has no tint: italic and faint, or folded to an italic `Thinking...`.
    The spacing rule of 10 therefore reads: a block gets the empty block above it when it and the block before it are both tinted (tool after tool, tool after user, user after tool); answers and thinking never do.

## Where it stands

Started, not finished.

- Done: a row can carry accents (a run of columns in a style of its own over the row's) and the rest of a tinted row is filled in the row's background (`ScreenComposer.Line.accents`, `spans(of:highlight:)`); `--verbose`/`/verbose` and ADR-0119 (what the status and the startup say). `ModelQualifier` gives `provider/model`.
- Done (step 1): the status line as prioritised segments fitted to the width, whole/shorter/gone and never cut, compact `provider/model/effort` label, `↑ ↓` usage, no `ready`, ⚠ accent, copy notice only on failure, `--verbose` shield. The probes still wait for `ready` and `ask>`; step 5 moves them.
- Done (step 2): the status line is below the input: picker, input, status, runner strip; the pointer regions, picker geometry and cursor follow.
- Next, in order, each its own commit with its tests: (a, done) the status line as prioritised segments fitted to the width, compact label and usage, no `ready`, ⚠ accent, failures-only copy notice; (b) the status below the input and the geometry that follows (pointer regions, picker, strip; the tests that name rows); (c) `ui.prompt`, the input tint and the separator row; (d) the block model: padding, spacing, tints, thinking style; (e) the ADR superseding 0015's lines, and the scripts that wait for `ask>` (`measure-*.py`, the probes) moved to something that survives `ui.prompt` being empty.

## Things to settle before (d)

- **Tint colours.** A terminal has no alpha: "semi-transparent dark" has to be a colour computed from the terminal's own background (OSC 11), or a fixed guess. With a guess, a light terminal gets dark bands. The kit has the query (`OSCPalette`); whether the screen's session delivers the replies is the first TerminalKit question (see `docs/research/terminalkit-handover-ui-2026-10.md`). Until then: a fixed dark-terminal set, a light set chosen from `COLORFGBG`, and `ui.tint = off`.
- **Scrolling a tinted transcript.** The transcript is a scroll region; a terminal fills the rows a scroll exposes with the current background. The kit resets style at the end of a frame, so it should be safe; a PTY probe has to show it (a tinted tool block scrolled off the top, no band left behind).
- **Padding spends rows.** Roadmap 0015 measured 47% of rows left for content in a transcript of one-line blocks with one-row padding; the owner chose it then and asks for it again. Re-measure on the real screen.
- **Selection and copy** must still contain the text and not the padding (ADR-0044): padding rows carry no `source`.
- **Glyph widths.** `⚠` and `⛨` have ambiguous or emoji width on some terminals; the screen uses the kit's width tables, so a disagreement misplaces the rest of the row. Probe in kitty, Terminal.app, ghostty, wezterm.
- Both layouts stay first-class (ADR-0008): the pixel separator is a refinement of the box-drawing row, never the only way to see the boundary.

## Done when

The status line fits every width from 20 to 200 columns without cutting a piece, a test per width class; the input and blocks match the model above; a PTY probe shows the scroll case; the ADR supersedes the lines of 0015; the budgets (input delay, action delay) are re-measured and written down.
