---
status: in-progress
blocked-by: ["0199", "0203"]
date: 2026-11-04
---

# 0204 — MarkdownLook: edit a Markdown file with a live preview, and follow a file changed elsewhere

The app half of "edit and see at typing speed" (owner, 2026-11-04), in `AemiMarkdown/Apps/MarkdownLook`, on the viewer kit (0199) and the edit API (0203). Design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 7. The lab (0207) is the debug counterpart of this pane pair and shares its source and preview components; bundle identifier `studio.aemi.MarkdownLook`.

## What is built

- A source pane and a preview, side by side or one at a time: the source is a plain-text editor (system monospaced font, 1.0 of the body size), coloured from the inline tape by roles, never rewriting the text; the preview is the viewer kit. An edit becomes `replace` on the document, the change set updates only the changed blocks, and the frame is handed to the display within the budget.
- **Source and preview together**: a caret offset finds its block by binary search on the source ranges and scrolls the preview to it (the scroll anchor of 0199 keeps the reader still when a block above changes height); a click in the preview finds its source offset from the run's range. Selection in the preview copies Markdown source.
- **Follow a file changed elsewhere**: the file is watched with a system API (a dispatch file-system source or `NSFilePresenter`, never a subprocess) and reloaded as an edit of the changed region; an unsaved local edit is never overwritten silently, the conflict is shown.
- Saving is atomic and never writes without the user's action or a stated autosave setting; reading never writes (the family's rule).
- **Anywhere.** The caret can be at the start, in the middle or at the end; the edit path, the preview update and the scroll sync are the same at every position, and the position series of 0203 is the test. An external save is applied as hunks from the last to the first (Aemi's diff), so a change in two places is two small edits and not one big one.
- A diagram in an edited fence keeps its last drawing until the new layout is ready; an unchanged fence is not laid out again (content hash).

## Red first, and measured

- The latency script types at the start, in the middle and at the end of each document and reports p50 and p99 per position.
- Signposts from the key event to the frame handed to the display; a script types into documents of 23 KB, 103 KB, 1 MB and 5 MB and reports p50 and p99 (target: 4 ms p99, release, quiet machine); a test that typing in a document leaves every other block's layout cache entry untouched.
- The text editor's own cost is measured too: TextKit 2 showed a 30 to 40 ms tail at 0.5 M characters and above (diary, claim 11), so the source pane for large files is a probe of its own and may be an own windowed editor.
- Conflict, rename and delete of the watched file are tested by events, not by sleeping.

## Done when

Typing in the source pane updates the preview within the budget at the four sizes; the file watcher follows an external save; nothing is lost on conflict; the numbers are in the diary.

## Not in scope

Undo beyond the text view's own, collaborative editing, a sync with other editors' buffers, an outline or table of contents, export beyond the PDF the vector drawing already gives.

## Progress (2026-11-05)

The lab is in the app (option-command-L): a text view reports each change as a byte range, `MarkdownEditor` re-reads the blocks around it, the page is made from what the editor holds, and a readout shows blocks removed and inserted, the parse time and whether the whole document was parsed. 300 random edits each matched a fresh parse. Not done: edits from outside (a file changing under the editor), undo of whole-document operations as one change, a measured latency through the view (one reading only).
