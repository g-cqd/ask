# UI lab

A disposable prototype of ask's screen, used to try layouts, separators, colours and the input grammar in a real
terminal before any of it is built (roadmap 0015, 0048). **Everything in it is fixture data.** It sends nothing,
runs nothing and talks to no model; it is not ask and shares no code with it.

```sh
python3 development/prototypes/ui-lab/lab.py          # needs a terminal at least 76 x 26; kitty for pixel lines
python3 development/prototypes/ui-lab/lab.py --check  # the self-test, no terminal needed
```

`Esc` switches between typing and browse keys. `s` (browse) or `/theme` (typing) opens the settings; the rest of the
keys are listed in the top row. Settings are saved to `/tmp/ask-ui-lab/settings.json` (`LAB_SETTINGS` overrides).

What `--check` pins: that nothing is ever painted (no background escape code, in any layout, popup or terminal), that text colours
are readable on the terminal's own background, one block model with the same padding in every layout (and the input), no leading
icon or bar, one stroke (not two) between the transcript and the sidebar, nothing under a popup, the `/` and `@` rules, routing
to a session, and the settings round trip. What it cannot show: clicks, selection and folding (roadmap 0051), that the hierarchy by type reads well, how any of this behaves
in ask's own input, or how it looks on a terminal other than kitty.
