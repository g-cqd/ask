---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0233 — File checkpoints: `/rewind` restores the files the tools changed

From the study of other agents (`development/research/capabilities-vs-peers-2026-11.md`, proposal 1), chosen 2026-11-13.

Each `write` and `edit` keeps the file's previous content in the session's store (sealed for an encrypted session, as pictures are),
recorded with the entry; `bash` changes are kept when they can be told (files the command names, a snapshot of the project's
tracked files is not taken). `/rewind` to a point offers to restore the files changed after it, showing which; a file changed since
by the person is said, not overwritten silently.

## Done when

A probe: an edit, a rewind with restore, the file back byte for byte; an encrypted session's copies are sealed.
