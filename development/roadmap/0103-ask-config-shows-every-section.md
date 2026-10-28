---
status: done
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

## Result

`ask config` lists every `ui` key (the name a file uses, the effective value from `ScreenOptions`, and `[default]` or the layer that set it),
the three `skills` keys and the MCP servers, whether or not a file sets them. Each layer records the keys it set (`Configuration.keySources`),
so a project file's `ui.padding` and the user file's `ui.tint` each show their own file. Tests: `ConfigurationKeySourceTests`.
