---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0236 — Diagnostics after edits: the checker's new errors return with the edit

From the study of other agents (proposal 5), chosen 2026-11-13.

After `edit` or `write`, the project's checker runs (a configured command such as `swift build`, or an LSP server when one is
configured) and the errors new since before the edit go back with the tool result, bounded; a slow checker runs in the background
and its result joins the next request. The check hook (0192) runs a command at `run.stop`; this is the same at each edit.

## Done when

A probe: an edit that breaks the build gets the error in its result; one that fixes it says so; a 30-second checker never blocks.
