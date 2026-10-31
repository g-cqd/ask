---
status: in-progress
blocked-by: []
date: 2026-10-27
---

# 0078 — Tool blocks use semantic payloads and configurable output folds

Refine tool presentation without changing tool identity, execution or persisted
input. This follows the full-input batch: the owner now prefers no input/output
section labels or rules, and more meaningful metadata and output folding.

## Still owed

- Read windows use `[x:y]` instead of `lines x–y`, with documented inclusive bounds
  matching the actual returned window. Keep target/path separate from this interval.
- Remove input/output divider labels entirely. Input is full-brightness/default
  foreground (white in the current theme); output is subtly dimmed. Preserve
  indentation, wrapping, whole-tool folds, heredoc folds and copy provenance.
- Present tool payloads semantically, not as raw serialized argument objects.
  Format structured JSON through AemiJSON with stable, readable indentation;
  render commands, source/file content and strings as their actual text. Formatting
  metadata must not change shell semantics, file bytes or copied original content.
  Define readable projections for read/write/job/skill and arbitrary MCP payloads.
- Add UI settings for maximum unfolded output lines and bytes, enabled by default.
  Assess defaults (starting candidates: 200 lines and 32 KiB), then document the
  effective rule when either limit is exceeded. Collapse the **center**, keeping
  useful head and tail context, with an explicit hidden-line/byte count.
- The center marker expands/refolds independently of the whole tool and of input
  heredocs. Support mouse and keyboard, tiny screens, streaming jobs and replay.
  Fold choices must survive updates; visible-copy excludes hidden content and all
  visual decoration. Full inspection must remain available through retained text
  or the actual output file, not by silently defeating bounded snapshot storage.
- Keep UI folding separate from tool-result truncation and the transcript's existing
  hard cap. Never claim folded content is expandable if the original has been lost.
- Hide irrelevant response-line counts for write/edit. That current `1 line` counts
  the tool's one-line acknowledgement, not the written file, and is misleading.
  Carry typed operation facts (bytes/file size/replacement count) to the UI rather
  than parsing result prose. Shell/read statistics should describe actual payloads.

## Byte display assessment

Prefer IEC units with correct capitalization: `KiB`, `MiB`, `GiB`, not `kiB`.
Recommended default: human-readable plus exact bytes, e.g. `1 KiB (1,024 B)` or
`1.5 KiB (1,536 B)`; below 1 KiB show just `512 B`. Avoid excess decimal precision.
Offer a UI choice between compact, exact bytes, and both if the extra verbosity
proves useful. Localize numeric grouping deliberately and inject locale in tests.
Distinguish resulting file size / total bytes written from changed bytes in an
exact replacement; do not label one as the other.

Acceptance includes red/mutation controls for off-by-one intervals, Unicode byte
counts, marker counts, head/tail bounds, fold independence, late job updates,
pretty-printed payloads versus original copies, and no write-result `1 line`.
Reusable formatting/search primitives belong in Aemi subpackages (roadmap 0076).

## Progress (2026-10-31)

Already in place before this pass: read windows as `[x:y]` (inclusive, from `offset` and `limit`); no input or output labels, input
in the default colour and output dimmed; a write's size in its header; no `1 line` for a write.

Done now, each test first:

- **No `1 line` for an edit either:** its one-sentence acknowledgement is not counted (`BlockProgressTests`; a read still counts).
- **Sizes past KiB:** `MiB`, `GiB` and `TiB`, one decimal at most, the exact count beside them, the unit chosen after rounding so
  1,048,575 B reads `1 MiB (1,048,575 B)` and not `1024 KiB` (`ToolPresentationTests`).
- **Unknown tools' input** (MCP servers' and any other without a known field) is shown as JSON indented by two spaces, keys in the
  model's order, and it parses back to the same value. The session keeps the call's own bytes; if encoding fails the bytes are shown.
  An approval's MCP detail stays compact: it is folded to its first row, and `{` alone would say nothing.
- The unused label helper is gone.

## Still owed

- Collapsing the centre of long output, with UI settings for the most lines and bytes left unfolded, a marker that unfolds on its
  own, and the rest of the acceptance above.
- An edit's replacement count as a typed fact in its header, not only in the result's sentence.
- Strings inside unknown tools' JSON are shown escaped (`\n`), not as their text.

