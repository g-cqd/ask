---
status: done
blocked-by: []
date: 2026-11-11
---

# 0220 — Name the conversation, and title the terminal's tab with it

The owner, note n60 (2026-11-09, task t235): "the first name would be processed from the first user request, and then we would
update it through processing each compaction. the default model to use to do that job would be the apple on-device foundation model
so that it would be free of charge. and we could title the tab reported to the terminal in that way". Note n49 (2026-11-06) asked for
the tab's name, from the path or from such a name.

## The owner's answers (2026-11-11)

1. **Without the on-device model:** the folder's name. The conversation stays unnamed; the tab says the folder.
2. **The tab reads** `ask · name`.
3. **Before a name:** `ask · folder`.
4. **Where the name shows:** the tab, and the session lists (`/resume`, `ask sessions`). Nothing else.

## The plan, as built

- The name is a rename of the conversation, kept as a thread record under the id `conversation`, which no thread has: a build that
  reads only threads' renames passes over it, and an older build reads the file as before (an unknown event would have failed it).
- `ConversationNaming.source`: a turn's start names an unnamed conversation from its first request, once a session per run; each
  compaction's summary names it again. `ThreadNamer` asks the on-device model, as for threads, with its two-second limit.
- `TabTitle`: OSC 0, which sets the icon name and the window title both, since terminals title tabs by one or the other. The
  terminal's title is pushed on its title stack (XTWINOPS 22) before the first and popped (23) when the screen closes. Control
  characters in a name are dropped. The title is written from a queue of its own, never the screen's thread (note n18).
- `SessionSummary.described(limit:)`: the name, then the first request, so a list still finds a session by what it began with.

## Done when

The tests and the probe fail on the build before and pass. They do: `ConversationNameTests`, `ConversationNamingTests`,
`TabTitleTests`, and `Scripts/probe-tab-title.py` (6 checks through the release binary).

## Not done

- A terminal without a title stack keeps `ask · …` after ask closes, until something else sets it.
- Whether the on-device model's names read well is not judged; on this machine it named "fix the login redirect" `login fix`.
- Not checked in a real terminal.
