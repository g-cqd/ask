---
status: accepted
date: 2026-10-23
---

# 0069 — The `@` file picker inserts a path, and lists only what ask may read

## Context

ADR-0067 built the `/` picker for commands and left `@` for files, agents and sessions. Roadmap 0048 says a file is "resolved at send
time against the project root, with an optional line range", that a path the sandbox does not let ask read "is not offered, and the
picker says why", and that the attachment is data, never an instruction. Agents and sessions need a transport and a sub-agent seam
that do not exist.

## Decision

1. **`@` opens the file picker at the start of any word** (`CompletionTrigger` already knew this rule), reusing the picker of ADR-0067:
   the same keys, the same window, the same rows. A `PickerRow` and a picker `Kind` generalise it; commands behave exactly as before.
2. **Choosing inserts text and nothing else.** Enter or Tab puts `@path ` in the draft and never sends. No file is read and nothing is
   attached: the model sees `@path` in the prompt and reads the file with its own tools, under the sandbox. The roadmap's send-time
   attachment would change the agent loop and the closed session payload, so it is a separate decision and is **not** built here.
3. **A `:12-30` typed after the path is kept** on whatever path is chosen. A name with whitespace in it is inserted quoted,
   `@"My Docs/a b.txt"`, because a space would end the word. A path typed in full closes the list, as a command name does, so Enter
   sends the prompt as it always did.
4. **The files are listed off the input path.** `ProjectLister` (in `AskTools`) asks git for its own list, tracked and untracked but not
   ignored, so `.gitignore` means what the user thinks it means; outside a repository, or if git does not answer in five seconds, it walks
   the directory, skipping version control, build output and tooling directories by name. It keeps 20,000 files at most and says when it
   cut. It runs on its own thread, because both the walk and the per-path canonicalisation block.
5. **Every path goes through the sandbox's read policy.** A file ask may not read is counted, never named, and the title says how many
   (`3 hidden by the sandbox`). A name is a small disclosure; the tools still enforce at read time, so a link that escapes the policy is
   refused there as before.
6. **The listing reaches the screen as data.** The controller asks with an `indexFiles` effect when an `@` word first appears and the
   listing is missing or older than ten seconds; the answer is a `ConversationUpdate`. Until it arrives the picker is one line,
   `files · looking for files…`, that takes only Escape, so a keystroke never waits. An old listing keeps serving while a new one loads.
7. **Ranking** is four groups, each in listing order: a path that starts with the query, a file name that does, a file name that
   contains it, a path that does; case ignored; 200 matches at most, and the title says `first 200 matches` when it cut. The paths are
   kept lowercased end to end in one buffer, with where each starts, so a keystroke is one libc `memmem` over the buffer and only a path
   that holds the query is looked at again to tell the groups apart. A hit that runs over the end of one path into the next counts for
   neither. The search stops once the best group is full.

## Not decided here, and not built

Agents and sessions after `@`, a skill list, attaching a file's contents at send time, a detail pane, clicking a row, and a walk that
honours a `.gitignore` outside git. Promoting the trigger and the ranking to TerminalKit now has its second consumer; that is the next
move for the kit, not for this change.

## Probes

Unit tests for ranking, the controller, the composer and the lister (real temporary git repositories, a real sandbox deny rule); a
real-binary PTY probe (`Scripts/probe-files.py`) with a negative control, including a file created after the first listing found once
the listing has aged. Mutation results and measurements are in diary 2026-10-23 (18).
