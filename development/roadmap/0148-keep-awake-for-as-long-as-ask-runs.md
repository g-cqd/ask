---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0148 — `keepAwake: "always"`: awake for as long as an ask process runs

Owner wish (2026-10-29 16:17): "Add an always option for keepawake that would literally keep computer up as long as an ask process is
running — it should block from any shutdown like update or such."

Today (0090, done) `keepAwake` is `off`, `system` or `display`, held through `ProcessInfo.beginActivity` while a turn or a job runs.

## Owed

- **The cheap half:** `always` holds the activity from launch to exit, idle or not; the assertion dies with the process, so a crash
  leaves nothing behind. A test like 0090's (taken at launch, kept between turns), and `pmset -g assertions` checked by hand.
- **The other half needs an investigation first, and may not be possible.** A power assertion stops idle sleep; it does not stop a
  restart someone asks for, and a command-line process cannot veto a shutdown (a GUI app can delay one through
  `applicationShouldTerminate`; launchd sends a terminal program SIGTERM). To find out, on this machine: whether a held assertion defers
  the automatic restart of a scheduled macOS update, what `softwareupdate` and the update scheduler respect, and whether anything short of
  a GUI helper or administrator settings can do more. Report what is possible before building anything beyond the cheap half.
