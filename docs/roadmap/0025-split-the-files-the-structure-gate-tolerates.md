---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0021
---

# 0025 — Split the files the structure gate still tolerates

ADR-0021 enforces one type per file, named for it. Four files break that today and sit on
`SourceStructure.knownViolations`, because the interactive-screen work (0013) was editing them and a split
underneath it would have made that work unmergeable.

| File | Types it declares | Becomes |
|---|---|---|
| `Sources/ask/AskMain.swift` | `Ask`, `Login`, `Logout` | `Ask.swift`, `Login.swift`, `Logout.swift` |
| `Sources/ask/PrintRun.swift` | `ClaudeProvider`, `PrintRenderer`, plus `runPrompt` | `ClaudeProvider.swift`, `PrintRenderer.swift`; `PrintRun.swift` keeps the free functions |
| `Sources/AskTUI/InteractiveScreen.swift` | `ScreenSession`, `ScreenEvent` | one file per type |
| `Tests/AskTUITests/TerminalTeardownTests.swift` | the suite and `IdleConversation`, `RecordingConversation` | nest the doubles in the suite, or give a shared one a file |

`AskTUI.swift` was split on 2026-10-19 (diary 09): it was not in the other branch's way. `AskMain.swift`,
`PrintRun.swift` and `InteractiveScreen.swift` are all edited on `robust-runs`, and `TerminalTeardownTests.swift`
too, so they wait for it to land.

## Done when

The four entries are gone from the baseline, `the baseline names only files that still break a rule` still
passes with an empty set, and the set itself can then be deleted so the gate has no escape hatch.

## Notes for whoever does it

`Scripts` for the mechanical split are not kept; the recipe is in `.agents/skills/ask-structure`. Expect the
compiler to demand: imports chosen per file (an unused `public import` is an error here), and `fileprivate`
members that cross the new file boundary made `internal`. Do it as its own commit, apart from any behaviour
change.
