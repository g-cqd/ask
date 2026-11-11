---
status: done
blocked-by: []
date: 2026-11-11
---

# 0222 — Tell the person when ask is done, or waits for them

The owner, note n62 (2026-11-09, task t252): "feat: (configurable) a way to notify the user about a session work being done, with
either a bell, or native notification".

## The owner's answers (2026-11-11)

1. **Default:** off.
2. **When:** only while the terminal is not focused; at a turn's end, and when ask waits for an answer (an approval, the model's
   questions).
3. **A terminal that does not report focus:** taken as not focused; notify anyway.
4. **Native:** through the terminal; ask launches nothing.

## The plan, as built

- `ui.notify`: `"off"`, `"bell"`, `"notification"`. The key's name is mine.
- Focus reports (`?1004`) are asked for only while it is on, so nothing changes with the default.
- A turn's end notifies when no queued message starts at once; an approval or questions when shown, a thread's too.
- The text is the tab's title and what happened: `ask · login fix: done`, `…: waiting for your answer`.
- How a notification is sent, mine: OSC 9 to iTerm2, Ghostty and WezTerm, kitty's own OSC 99, OSC 777 to the rest. Terminal.app reads
  none of them, so it gets the bell, which it marks the tab and the Dock with. All of it goes from `TabTitleWriter`'s thread.

## Done when

`NotifyConfigurationTests` and `NotifyTests` fail on stubs and pass; `Scripts/probe-notify.py`, 5 checks through the release
binary, passes, and the build before fails it.

## Not done

- Whether each terminal shows the notification is not checked: that is the terminal's, in a real one.
