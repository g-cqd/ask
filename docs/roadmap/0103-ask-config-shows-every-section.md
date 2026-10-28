---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0103 — `ask config` shows every section, with its defaults

Owner remark (2026-10-28): `ask config` does not show the `ui` settings. It prints `ui`, `skills` and `mcp` only when a file sets something,
and then only the keys that file set, so the defaults are invisible and the README's "shows each value and where it came from" is not true.

## Plan

- Show every `ui` key with its effective value and source (`[default]`, the file, a flag), from the same defaults the screen uses
  (`ScreenOptions()`), so a default changes in one place.
- Show `skills` (enabled, how many are advertised, the sources) and `mcp` (the servers named, or none) the same way.
- Tests on the report: an empty configuration lists every `ui` key as `[default]`; a file's key shows its source.
