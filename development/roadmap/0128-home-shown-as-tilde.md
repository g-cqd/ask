---
status: done
blocked-by: []
date: 2026-10-28
---

# 0128 — The home folder is shown as `~`

Owner wish (2026-10-28 23:02): wherever ask shows a path that starts with the user's home folder (tool headers, `ask config`, notices),
show `~` instead. Never in a file's content or in a command as it was run: those stay verbatim. Test-first, a red test before the change.

## Result (2026-10-28)

`HomePath.abbreviate(_:home:)` writes `~` for the home folder at a path boundary only (not `/Users/gigi2`, not `/tmp/Users/gigi/x`). It is
applied to ask's own words: notices, details (with `--verbose`), approval questions, a non-command tool's header summary, and the output of
`ask config` (`/config` goes through notices). Not applied to a command as it was run, a tool's input or output, file content, the
user's prompts, the model's text, nor the resume command and `ask -p`'s session line, which a person copies into a shell. Written red
first: `HomePathTests` did not compile until the type existed. The screen gets the home from `ScreenOptions.home` (the launch
environment's `HOME`).

