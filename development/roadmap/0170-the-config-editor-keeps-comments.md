---
status: not-started
blocked-by: []
date: 2026-10-31
---

# 0170 — The `/config` editor keeps the file's comments

Found while closing 0116: the editor reads the configuration as JSON5 and writes it back as strict JSON
(`ConfigEditor+Write.swift`, `commitTyped`), so the first change made in `/config` silently drops every comment, along with
trailing commas and unquoted keys. `ConfigEditorModelTests` pins this today ("comments are not preserved").

Owner (2026-10-31): preserve the comments, rather than ask before saving or warn in the editor.

## Still owed

- An edit that changes only the bytes of the value it sets: find the setting's span in the source, replace it, and add or remove a
  key with the file's own indentation and separators. This most likely belongs in AemiJSON, as a JSON5 parse that keeps source
  ranges. Decide where once the AemiJSON API is checked.
- Turn the pinning test around: a commented JSON5 file keeps its comments, trailing commas and key style after a change, and a
  removed key takes its own comment line with it.
- Keep what the editor promises today: the result still parses as the configuration, the write is atomic, and the file's mode is
  kept.
