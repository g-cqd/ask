# Terminal Markdown renderers, run against edge cases (2026-10-25)

Method: run the program, never trust its source. Subject: **glow 3.0.0** (Homebrew, `/opt/homebrew/bin/glow`), which renders with glamour on
goldmark. Always `glow -s dark -w 80 FILE </dev/null`; **without `</dev/null` a captured run printed 2 bytes and looked like a result**
(a probe that could not fail the right way, caught by checking the output size).

| Input | Result |
|---|---|
| Ordinary document (396 B) | 17,939 B out (45x); 22 ms |
| The same, repeated 100x and 400x (40 KB, 158 KB) | 1.9 MB and 7.6 MB out (48x); 0.41 s and 1.59 s, about 100 KB/s |
| `*a ` x 20,000 and x 40,000; `[` x 20,000 and x 40,000 | Linear, 0.14 to 0.25 s; no quadratic blow-up from delimiters |
| `>` x N, then ` x` | N = 8 to 28: 0.02 to 0.05 s; N = 48: 0.13 s; N = 56: 0.28 s; **N = 100: not finished after 30 s** |
| 1,000 nested list levels (1 MB) | Not finished after 40 s |
| A raw `ESC ] 52 ; c ; ... BEL` in the text | **Written to the terminal unchanged**, so a Markdown file can set the clipboard |
| A raw `ESC [ 3 1 m` in the text | The ESC passes; the rest is drawn as text, so the sequence is live |
| `[text](https://x "title")` | OSC 8 with `id=` and a BEL terminator; the target is then printed again, underlined, after the text |
| A bare URL | Becomes an OSC 8 link |
| Styles | Every space is wrapped in its own SGR set and reset, which is where the 45x comes from |
| `-s notty` | Inline markers inside a heading stay raw (`**bold**`) |

What ask takes from it: show the target of a link; hide nothing that decides where a click goes; limit depth; neutralise control bytes before
parsing; let the cell diff write the bytes, so a space costs nothing. What it does not settle: how swift-markdown or a hand-written parser
behave on the same inputs (roadmap 0065, phase 0).

Reproduce (the timings are one machine's, medians of 3): generate each input with a short script, write it to a file, run the command above
with a timeout.
