---
status: in-progress
blocked-by: []
date: 2026-11-08
---

# 0215 — Paths in replies: resolved, shortened, clickable

The owner, 2026-11-04 (note n31, task t214): outside tool output and search results, resolve relative and absolute paths against the
workspace. Show them relative when they are inside it, or when they share an ancestor up to N levels up (on by default, N = 2,
configurable, "no limit" allowed). Make them clickable to open. Safeguards (note n33): a path the model writes is shown, and never
opened or run without the person's click; nothing outside what the sandbox may read is resolved or stat'ed silently. This relates to
`PathLinks` (0075).

## The owner's answers (2026-11-08)

1. **Copying** a shortened path copies the full path.
2. **A relative path** the model writes (`Sources/a.swift`) is linked only if it exists. The check is a cached stat, only inside what
   the sandbox may read.
3. **Where:** model replies, ask's notices and thinking blocks. Not the person's own messages, tool output or search results.

## What is there today

- `PathLinks` links `/…` and `~/…` words in plain rows, and `MarkdownLinks.resolve` links Markdown link targets.
- Both show the text as written. A relative path is never linked, since a row does not know its directory.
- In a Markdown row each drawn run keeps the source bytes it shows (`StyledRun.source`, ask's `RowSegment`), and a selection copies
  those bytes. An entity already draws text that differs from its source.

## The plan

1. **TerminalKit: a path hook in the Markdown renderer.** `MarkdownLinks.paths` is a host function from a run of prose text to the
   paths in it: each one's byte range, the text to show, and its URI. `InlineCollector.verbatim` splits a prose piece around each path.
   The path becomes a piece showing the shown text over the source range of what was written, with its link, the way an entity
   shows its decoded character. It applies outside code spans and links. Red first in TerminalKit's own tests, then the pin moves in
   ask's four manifests and locks.
2. **ask: `PathDisplay`, the resolver** (AskTUI, pure, given the workspace, home, the ancestor limit and an existence check):
   - An absolute or `~/` path inside the workspace is shown relative to it.
   - One sharing an ancestor at most N levels above the workspace is shown as `../…`.
   - Any other path is shown as written.
   - A relative path is linked only if the check says it exists under the workspace. The check is a stat, cached per path for the
     session and confined to the workspace, so nothing outside the sandbox's reach is touched.
   - A `:line` or `:line:column` suffix is kept on the shown text and dropped from the URI, as `PathLinks` does.
3. **Copying.** Because the shown text stands over the written source, a selection copies what the model wrote. An absolute path
   copies in full, as the owner chose. A relative one copies as written. Making that one full too needs a copy override per
   segment; that is step 6.
4. **Where.** Replies and thinking go through the Markdown hook. A notice is a plain row: its absolute paths keep their text and
   gain links through `PathLinks`, and they are shortened only if notices move to the Markdown renderer.
5. **Settings.**
   - `ui.paths`: `"short"` (the default) or `"asWritten"`, which keeps today's text and links only.
   - `ui.pathAncestors`: an integer, default 2, or `"any"`.
6. **Still required by the owner's answers:** a relative path copies in full, and notices are shortened too.

## Done when

- The TerminalKit hook is tested and pinned.
- `PathDisplay` is tested: inside, ancestor within N, beyond N, home, relative existing and missing, `:line`, and no stat outside
  the workspace.
- A reply showing `/…/project/Sources/a.swift:12` draws `Sources/a.swift:12`, links it, and copies the full path.
- A PTY probe checks the above, and the build before fails it. `docs/screen.md` and `docs/configuration.md` say so.

## Not in scope

Openers and the confirmation of what a click runs (t215, note n32), which needs a design record of its own. Tool output and search results.

## Progress (2026-11-08)

- Step 1 is done: TerminalKit 37d0143 adds `MarkdownLinks.paths` and `MarkdownPath` (`MarkdownPathTests`, 4, red first), and ask
  pins it in its four manifests and locks. Nothing in ask uses it yet.
- Next: `PathDisplay` and the settings (steps 2 and 5), then the probe.
- Steps 2 and 5 are done (2026-11-08):
  - `PathDisplay` and its scanner (`PathDisplayTests`, 7, red on a stub), with `PathExistence` caching the stat.
  - The settings `ui.paths` and `ui.pathAncestors` (`null` for no limit; `PathSettingsTests`).
  - Replies and reasoning use the hook. The person's messages and summaries do not (`ReplyPathsTests`, 5).
  - `probe-reply-paths.py`: 4 checks, which the build before fails.
- Found by the probe: the Markdown parser splits a text at `_` runs that are not emphasis, so a path with an underscore reached the
  hook in pieces. TerminalKit ccac505 runs the hook over each stretch of adjacent prose, and has a test with underscores.
- Links keep `PathLinks.uri`'s standardised form (`/private/var/…` is written `/var/…`), the same file.
- Left: notices are linked but not shortened (step 4); a relative path copies as written, not in full (step 6).

## Safety follow-up (2026-11-10)

The former lexical workspace guard and TUI fileExists cache did not enforce read policy or prevent symlink traversal.
ReplyPathExistence now belongs to AskTools, called through Conversation with the current policy and session narrowing.
No host policy means no relative lookup. Policy/workspace changes invalidate the per-conversation bounded cache; descriptor-relative
walks refuse symlinks. Relative references through symlinks remain text. This does not claim live invalidation for changed files.

## Still owed

- Real-terminal checks are deferred. The safety follow-up passed the full release/quality gate (3,779 tests); mutation is CI-only.

## Copy follow-up (2026-11-10)

Whole accepted relative prose references now expand to absolute workspace paths when copied, after source-coordinate slicing.
Both automatic drag copy and Ctrl+C use it; partial references, user/tool text and Markdown code/explicit links remain literal.
Location suffixes and punctuation are preserved. Regression and full-gate results are recorded in diary 2026-11-10-07.
Notice shortening remains owed; notices may already expand complete relative references on copy.

## Notices (2026-11-10)

Step 4 is done: a notice's paths are shown short and linked, as plain text (`NoticePathRows`), with `ui.paths` `asWritten` leaving
them alone. A selection copies the notice as it was written, the full path included (`NoticePathsTests`, 4, two red before).

## What is left

- Paths inside inline code and fences are left as written, by choice of the hook; the owner has not asked for them.
- Real-terminal checks, which the owner deferred.
