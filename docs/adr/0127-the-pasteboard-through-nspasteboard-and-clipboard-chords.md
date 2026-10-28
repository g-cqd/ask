---
status: accepted
date: 2026-10-28
---

# 0127 — The pasteboard through NSPasteboard, and clipboard chords that never type

## Context

Command+C printed a `c` in the input (roadmap 0082). With the kitty keyboard protocol on, a terminal that has no selection of its own
(ask holds the mouse) passes Command+C on as `CSI 99;9u`: `c` with the super modifier. The editor knew ctrl and alt, not super, and typed
the letter. A paste the terminal passes on the same way needs ask to read the pasteboard; copies went through `pbcopy` (ADR-0046, ADR-0068).

The owner asked for the most current pasteboard API. Checked with `apple-docs` (corpus built on macOS 27): `NSPasteboard` is still the
system pasteboard API on macOS. SwiftUI's clipboard modifiers (`copyable`, `pasteDestination`, `onPasteCommand`) and `Transferable` sit on
top of it and need views and menu commands. The recent additions are pasteboard privacy (an alert when an app reads the general pasteboard
from code, unless the read came from a paste-related UI input), `accessBehavior`, and the `detect…` methods.

## Decision

1. Copy and paste go through `NSPasteboard.general`: `prepareForNewContents(with:)` then `setString(_:forType:)`; `string(forType:)` to
   read, after checking `accessBehavior`, so that `.alwaysDeny` is said in the transcript rather than failing silently. `pbcopy` is gone.
2. A Command (super) or hyper chord never inserts text. Command+C and Command+X copy and cut a selection (transcript or input) like Ctrl+C
   and Ctrl+X; with nothing selected they do nothing. Ctrl+C keeps interrupt and Ctrl+X keeps clearing the draft when nothing is selected.
3. Command+V and Ctrl+V read the pasteboard and paste it as a bracketed paste would. Terminals that paste Command+V themselves are unchanged.

## Consequences

- Measured: using NSPasteboard costs about 1 MiB of footprint (0.3 MiB once PDFKit has loaded AppKit) and about 2 ms for the first read,
  only after the first copy or paste. A copy is no longer a process.
- A read from code may show macOS's paste alert, attributed to the terminal, depending on the person's setting for it. On the machine it was
  built on, a terminal process reports `.alwaysAllow`.
