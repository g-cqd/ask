---
status: done
blocked-by: []
date: 2026-10-31
---

# 0170 — The `/config` editor keeps the file's comments

Found while closing 0116: the editor reads the configuration as JSON5 and writes it back as strict JSON
(`ConfigEditor+Write.swift`, `commitTyped`), so the first change made in `/config` silently drops every comment, along with
trailing commas and unquoted keys. `ConfigEditorModelTests` pins this today ("comments are not preserved").

Owner (2026-10-31): preserve the comments, rather than ask before saving or warn in the editor.

## Built 2026-11-12

The owner chose AemiJSON for the source ranges (2026-11-12). AemiJSON 806b481 adds `JSON.sourceRange` and
`forEachMemberWithKeyRange`, read from the tape it already builds (scalar offsets; container spans under
`recordsContainerSpans`); the family's pins follow it (AemiHMMML ed8469a, AemiMarkdown 81108b1, AemiMermaid 9941c38, TerminalKit
b726ad1). In ask, `ConfigSourceEdit` compares the file's tree with the tree to save and edits only what differs: a changed
value's bytes; a new member after the last one kept, in the file's indentation, key quoting, separator and trailing-comma style; a
removed member with its comma, its line's comment and the comment lines right above it; an old name with an unchanged value
renamed where it stands; an emptied section written `{}`. The result must parse as the settings to save, or the file is written
anew, as before. Atomic writes and the file's mode are as they were.

Proof: `ConfigEditorKeepsCommentsTests` (7; red against the old writer, 10 issues), `ConfigEditorModelTests` turned around,
`probe-config-editor.py` (7; the save keeps the comment and changes only the value's bytes; the installed binary fails that check).

Not done: an emptied section keeps no comment it held; a value rewritten (not renamed) loses the comment inside it.

