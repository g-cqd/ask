---
status: accepted
date: 2026-10-25
---

# 0093 — A session is navigated by going back to before one of its prompts

## Context

A session is a tree (roadmap 0008, ADR-0017): entries are never removed, the leaf selects the active branch, and a checkout
moves the leaf and is recorded. The model of it was complete and nothing in the screen used it: the only way to try a different
prompt was to start over. pi offers `/tree` and `/fork` for exactly this; ask had the data structure that makes it cheap and no
command.

## Decision

1. **`/tree` lists the session's prompts.** Only the prompts, which are the only entries a person wrote, as numbered turns in the
   order they were recorded (`SessionOutline`). Numbers never change, so one read in a listing still means that prompt when it is
   used, however many branches were added since. `>` marks the turns on the path the session is on; a turn sent after going back is
   marked `(branch after N)`, or `(starts again)` when it began from nothing. The listing shows the last 40 turns and says so; every
   number works.
2. **`/tree N` goes back to before prompt N.** The session's leaf moves to the entry that prompt followed (nothing, for the first),
   which is persisted like any checkout, the screen shows the conversation up to there, and **the prompt's text goes back into the
   editor**. The next message sent continues from that point as a new branch; the turns that came after stay in the session and in
   the listing. Nothing is deleted and the same session stays open, so jobs, the model, the narrowing the model made and the strict
   sandbox are untouched.
3. **A draft is never overwritten.** If the editor holds anything but whitespace when the prompt is returned, the draft stays and the
   prompt is shown in a notice. (A command is typed into the editor, so this arises only with text restored from an aborted run.)
4. **A number that is not a prompt is refused** with the range, and a session with no prompts says there is nothing to go back to.
5. **Only between turns.** Like every command, it is refused while a turn runs.

## Not decided here

`/fork`: a new session file holding the active branch (or the branch up to before a prompt), which `SessionFile.fork(to:)` already
writes. It is the next piece and has its own questions (the new file's name, jobs, whether the original keeps the branch).
Navigating to a point that is not a prompt, and showing the branches as a drawn tree, are left; the flat numbered listing says what
a person needs to choose.

## Probes

Unit tests for the outline (straight conversations, branches, starts from nothing, consecutive prompts, alignment past ten turns, the
listing's text), the recorder's persisted checkout, and the screen's draft rule; seventeen compiling mutants, all caught. The real
binary through a PTY with a fake provider (`Scripts/probe-tree.py`): a listing, going back, the prompt returned to the editor, a
changed resend, and the request the provider then receives, which holds the first turn and the changed prompt and nothing of the
set-aside one; with a control that does not know the command.
