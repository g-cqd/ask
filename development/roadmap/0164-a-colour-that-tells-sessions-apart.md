---
status: done
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

## Done (2026-10-30)

`ui.sessionColor`: `"off"` (default), `"always"`, or `"others"` (only while another process called `ask` runs on this Mac). The colour
is a hue seeded by the project's path and the session file's name (FNV-1a over the wheel, `SessionHue`), mixed into the terminal's own
page as the status line's background (`ScreenTheme.sessionTint`), the leading mark included. A new session's file name is chosen at
launch, so its colour holds from the first frame to the first prompt and after a resume. The setting is read every 3 seconds, so a change
to the file applies without a restart; `others` lists processes then (`proc_listallpids`). ask itself is not sandboxed (only its tools
are), so `others` works with the sandbox on, contrary to what the wish expected. One key, not two: the status line is the only place the
colour goes for now.

Tests: `SessionColourTests`, `SessionColorConfigurationTests`, the catalog and docs tests; `Scripts/probe-session-colour.py` (always is
coloured, off is plain, others is coloured beside a copy of `sleep` named `ask`; "others, alone" is skipped where other asks run, as on
the owner's Mac now). At the owner's request (the wish), `"sessionColor": "always"` is set in `~/.config/ask/config.json` (backup beside
it).

