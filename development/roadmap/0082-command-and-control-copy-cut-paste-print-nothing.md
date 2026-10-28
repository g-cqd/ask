---
status: done
blocked-by: []
date: 2026-10-28
---

# 0082 — Command and Control copy, cut and paste print nothing in the input

Owner request, from `ask-wishes.md`: on macOS, Command+C after selecting text with the mouse and copying
manually prints a `c` in the input. Command and Control C/X/V must work like copy, cut and paste and must not
insert any character.

## Still owed

- Reproduce first, with the raw bytes. Hypothesis, not checked: the terminal forwards Command+C as an
  extended-keyboard sequence (CSI-u with a super modifier) because ask enabled that protocol, and the decoder in
  TerminalKitInput keeps the base character and drops the modifier. Capture what each supported terminal sends.
- Decode the super and control modifiers for `c`, `x` and `v` as their own key events. A key with a modifier that
  the input does not handle never becomes text.
- Behaviour: Command+C copies the input selection (and does nothing to the input when there is none); Command+X
  cuts; Command+V and Ctrl+V paste, like bracketed paste does today.
- Ctrl+C keeps its meaning as interrupt (see 0083) when nothing is selected; say what wins when both apply.
- Tests in TerminalKitInput for the decoding, and in AskTUI for "no character reaches the input".

## Update (2026-10-28)

TerminalKit already has `KeyModifiers.super`, so the hypothesis above is narrower than it read: the kit may be decoding the chord correctly and ask (or the kit's router) may print the letter as well. TerminalKit roadmap 0020 item 1 holds the probe.

## Result (2026-10-28, ADR-0127)

- Cause confirmed in code, not in a terminal: `CSI 99;9u` decodes to `c` with `.super`, and `PromptEditor.apply` typed it. The kit was right.
- Command and hyper chords never type. Command+C/X copy and cut a selection like Ctrl+C/X, and do nothing without one; Ctrl+C keeps
  interrupt and Ctrl+X keeps clearing the draft when nothing is selected. Command+V and Ctrl+V paste the host pasteboard.
- The pasteboard is `NSPasteboard` now (copy and paste), checked against the macOS 27 documentation; `pbcopy` is gone. A denied paste says so.
- Tests: `ClipboardChordTests`, `HostPasteboardTests` (on a private pasteboard).
- Not verified: in a real terminal (Ghostty, iTerm2, Terminal, VS Code), which of them pass Command+C/V on at all; whether macOS's paste
  alert appears for a read triggered this way when the terminal is set to ask.
