---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0164 — A colour that tells sessions apart

Owner wish (2026-10-30 16:36): a way to tell ask sessions apart, as a colour on the session; the owner sets it to the status bar's
background in their own file. Off by default.

Two methods, chosen in the configuration:

- **Another ask is running:** a hue is applied when ask finds another ask process on the Mac. Looking for other processes is only
  possible without the sandbox (or with an allowance for it), so under the sandbox this method says it cannot look.
- **Always a colour of its own:** a colour picked at random but seeded by the project's path and the session file's name, so the same
  session always gets the same colour and two sessions rarely share one.

To settle before building, with the naming conventions of 0154: the keys (proposed `ui.sessionColor: "off" | "others" | "always"` and
`ui.sessionColorTarget: "status"`), how a hue is mixed with the theme so text stays readable on light and dark pages (the tints of
0074 already mix from the terminal's own colours), and whether a resumed session keeps its colour (it does, if seeded by the file).
