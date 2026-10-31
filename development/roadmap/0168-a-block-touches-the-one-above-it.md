---
status: done
blocked-by: []
date: 2026-10-31
---

# 0168 — A block sometimes touches the one above it

Owner report (2026-10-31): sometimes a block is drawn right under the previous one, without the blank row usually between them.

## Why

Two blocks that are both tool calls, the user's messages or ask's notices get a blank row between them
(`ScreenComposer.isSpaced`). So a block's rows depend on the block before it. The windowed layout lays a block out again only
when its own revision changes.

Some blocks change kind in place:
- a queued message becomes the user's message once the conversation takes it (`showSent`);
- one the conversation refuses becomes an error notice;
- reasoning stopped midway becomes a notice.

Only the changed block was laid out again. A tool that had started below a queued message kept its rows from when it followed a
queued line, which carries no blank row. Now that it followed the user's message, the two tinted blocks touched.

## Done (2026-10-31)

`Transcript.replace(at:with:)` changes a block in place and bumps the revision of the block after it too. The three places that
changed a block's kind use it. Test: `BlockSpacingCacheTests`, written first and red. It compares the cached window with a fresh
layout after a queued message is sent below a running tool.

Not seen in a real terminal; the owner's report did not say which blocks touched. A case with another cause, if one remains,
would need the blocks it happened between.
