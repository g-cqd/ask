---
status: done
blocked-by: []
date: 2026-11-11
---

# 0221 — Show a long action in the terminal's tab

The owner, note n59 (2026-11-09, task t251): "when an action is taking time, ask could report the progress directly to the terminal
so that the terminal can know and show progress activity"; note n61: "i'd like that the progress indicator shows in the terminal tab
name".

## The owner's answers (2026-11-11)

1. **When:** only long actions, not every turn. **Long:** after 5 seconds.
2. **What counts:** a whole turn, a compaction, a tool call or command. Not connecting MCP servers.
3. **The tab's name:** an animated spinner leads it while the action runs, for terminals without OSC 9;4.

## The plan, as built

- `ScreenController.isWorking`: a turn, a compaction, or a tool in the foreground (the person's `!` command outside a turn too). A
  background job and an aside are not; neither is reconnecting, which waits.
- `LongAction`: how long the work has gone on, anew each time it starts.
- Past five seconds, the frames of `ui.spinner` lead the title, four a second, from its first frame (`TerminalProgress.frame`).
- OSC 9;4 state 3, then 0, only to iTerm2 3.6+ and Ghostty 1.2+ (`TerminalProgress.isRead`), and not behind tmux. OSC 9 alone is a
  notification in iTerm2, kitty, Ghostty and others, so a terminal from before the progress form would show "4;3" as one. That
  limit is mine, from what OSC 9 is; the owner's answer 3 covers the terminals left out.
- All of it goes from `TabTitleWriter`'s thread (roadmap 0220); the busy mark is taken away when ask closes.

## Done when

`TerminalProgressTests` fails on stubs (17 issues) and passes; `Scripts/probe-terminal-progress.py`, 8 checks through the release
binary with a model that takes seven seconds, passes, and the build before fails it.

## Not done

- WezTerm, kitty and other terminals that may read OSC 9;4 get the spinner alone, until each is known to.
- Not checked in a real terminal.
