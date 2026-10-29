---
status: done
blocked-by: []
date: 2026-10-28
---

# 0126 — A shorter way to write a command's timeout

Owner wish (2026-10-28 23:02): find a more compact way to write the timeout in command headers (0080 writes `timeout 2 min`).

## To decide with the owner

Candidates, shortest first: `⏱2m` (a symbol and compact units), `2m` alone after the tool name, `≤2m`. Units would be `45s`, `2m`,
`1m30s`, `1h`. `ui.localizedDurations` may then only govern elapsed times.

## Owner's answer (2026-10-28)

The proposed short forms (`⏱2m`, `2m`, `≤2m`) are rejected. Do not use them. Still open: another approach, to be proposed as something other
than a cut-down spelling (for example dropping the word when the unit says it, or showing the timeout only when it is not the default).

## Proposal (2026-10-29), after the owner's yes to "show it only when it matters"

Two typed settings, in the spirit of 0118 (an enum and a bounded string, no free-form template):

- `ui.timeout`: `"auto"` (default), `"always"` or `"never"`. `auto` writes the timeout only when the call set one that differs from the
  default of 120 s, so the common case is `shell · <command>`, and an unusual limit stands out. `always` is today's behaviour. `never` hides
  it. The boolean form the owner suggested is `"always"` or `"never"`; `auto` is the third state a boolean cannot express. If a pure
  boolean is wanted, `true` = `always`, `false` = `never`, with `auto` as the default when unset.
- `ui.timeoutLabel`: the word in front of the duration, `"timeout"` by default, any string of up to 8 display cells, for a person who wants
  `⏱` or `t`. A bounded string rather than a template, so it stays checkable.

The yield limit follows the same two keys. To be confirmed with the owner before it is built.

## Done (2026-10-29)

Approved as proposed and built: `ui.timeout` (`auto`, `always`, `never`; `auto` hides a timeout equal to the shell tool's 120 s default,
and the yield is written unless `never`) and `ui.timeoutLabel` (1 to 8 characters, no control or format characters; the screen also cuts
it to 8 cells, so a wide character fits). Tests in `TimeoutDisplayTests` and `TimeoutConfigurationTests`; mutations (auto writing the
default, the label check accepting a newline) turned them red. `Scripts/probe-command-header.py` through the release binary: a 300 s
timeout is written, a 120 s one is not. Changes apply to blocks started after a configuration is loaded, as for `ui.localizedDurations`.
