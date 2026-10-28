---
status: accepted
date: 2026-10-20
---

# 0046 — The interaction defaults

## Context

ADR-0044 put interaction policy in the configuration and left every default but one open. The owner then answered the first
("starts folded") and asked for the rest to be assessed and decided from evidence. The evidence is TerminalKit's probe of four
terminals (its ADR-0028) and a count of code blocks, prompts and images in 8,248 + 6,881 + 24,994 messages of local agent
sessions (`development/research/ui-content-sizes-2026-10.md`).

## Decision

**Decided by the owner**

| Key | Default |
|---|---|
| `ui.thinking` | `folded` |
| `ui.tools` | `folded` (tool output, so a long result never pushes the answer off the screen) |
| `ui.copyOnSelect` | on |

**Decided on evidence, for the owner to overrule**

| Key | Default | Why |
|---|---|---|
| `ui.mouse` | on | Mouse reporting works in all four terminals tried, and every one gives the user back its own selection with a key (Shift; fn in Terminal.app), so taking the mouse costs less than it seems. It also stops the wheel turning into arrow keys. `off` gives the terminal its own selection and scrollback untouched |
| `ui.images` | `placeholder` | Images are in 0.06% to 0.58% of messages, so drawing them by default buys almost nothing and costs a block of screen. A click shows one. Terminal.app has no graphics, so it is always a placeholder there |
| `ui.codeFoldLines` | 20, and never more than half the viewport | 91% of 725 code blocks are 20 lines or fewer, so the common ones stay open and the longest 9% fold. Capping at half the screen stops a short window from showing a block that fills it |
| `ui.promptRows` | 6, and never more than a third of the viewport | Prompts are heavy-tailed (most one or two rows, a few very long), which argues for an input that scrolls inside itself and not for a different number. Six is unchanged from today |
| `ui.scrollLines` | 3 | A wheel report is one step, and terminals send 1, 3 or 9 reports for the same gesture (ADR-0028), so the host must choose what a step scrolls. 3 is a starting value to tune on a real trackpad, which was not measured |

**The clipboard.** Copying writes through OSC 52, and also through the system pasteboard (NSPasteboard since ADR-0127; `pbcopy` before) on a terminal that is not known
to take OSC 52, which includes Terminal.app, where OSC 52 was measured to do nothing (TerminalKit ADR-0028).

**The hint.** The status bar names the key that returns the terminal's own selection for the terminal in use, so the cost of
`ui.mouse` is never a mystery.

## Consequences

- These are values, not code: nothing here is built. They go into the configuration with the screen that uses them (roadmap 0051).
- Every key is overridable in the user file and, once trusted, the project file (ADR-0032), and `ask config` shows where each
  value came from.
- If the owner overrules a default, this ADR is superseded for that key and the others stand.

## What this does not decide

Whether fold state is saved with a session, what a runner list contains, hover, and how the character layout draws a click target.
Those are open in roadmap 0051.
