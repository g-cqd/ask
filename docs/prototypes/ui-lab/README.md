# UI lab

A disposable prototype of ask's screen, used to try layouts, separators, colours and the input grammar in a real
terminal before any of it is built (roadmap 0015, 0048). **Everything in it is fixture data.** It sends nothing,
runs nothing and talks to no model; it is not ask and shares no code with it.

```sh
python3 docs/prototypes/ui-lab/lab.py          # needs a terminal at least 76 x 26; kitty for pixel lines
python3 docs/prototypes/ui-lab/lab.py --check  # the self-test, no terminal needed
```

`Esc` switches between typing and browse keys. `s` (browse) or `/theme` (typing) opens the settings; the rest of the
keys are listed in the top row. Settings are saved to `/tmp/ask-ui-lab/settings.json` (`LAB_SETTINGS` overrides).

What `--check` pins: contrast on real terminal palettes, the bottom rows not moving when thinking is expanded, a
padded row above and below every surfaced block, one stroke (not two) between the transcript and the sidebar, compact
and aerial being different designs, the `/` and `@` rules, routing to a session, the settings round trip.
What it cannot show: how any of this behaves in ask's own input, or on a terminal other than kitty.
