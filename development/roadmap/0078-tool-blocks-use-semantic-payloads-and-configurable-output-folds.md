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

### Centre fold of long output (2026-10-31)

- **Rule:** an open tool block whose output has more than `ui.fold.outputLines` lines (default 200) or more than
  `ui.fold.outputBytes` UTF-8 bytes (default 32768) keeps a head and a tail that share the budget: half the lines each (the head
  takes the odd one) and half the bytes each, whole lines only, every line counted with its line feed. A single line too large for
  either end is hidden whole. Minimums are 2 lines and 64 bytes; lower values are refused by name. The defaults are the record's
  candidates, unchanged: nothing in the probes argued for others.
- **Marker:** one dim row between the two ends, `⋯ 290 lines hidden (2 KiB) · click to show`, and once open
  `⋯ 290 lines shown · click to fold`, cut to the width on a tiny screen. It is a decoration row with no source, so a selection
  copies the two ends (or the whole output, open) and never the marker.
- **Independence:** the choice is a code fold under ordinal `Transcript.outputFence` (−1), apart from the whole block's fold and the
  input's heredocs (0 and on). A click on the marker toggles only it; Ctrl+G flips it with every other long block. Being keyed by
  item, it survives later output (a job's updates). The header still counts the whole output (`300 lines`).
- **Nothing is lost:** the fold is a projection of the retained text, so opening it shows the real middle. It is separate from
  the transcript's 400-line hard cap, which still applies first and says so.
- Tests: `ShownToolOutputTests` (bounds, odd share, UTF-8 bytes, a too-large line; two mutations turn them red),
  `ToolOutputFoldTests` (marker, header count, copy, toggle, Ctrl+G, click; disabling the click branch turns it red) and
  `OutputFoldConfigurationTests`. Probe: `Scripts/probe-output-fold.py`, 5 pass through the release binary.
- On the side: `UISection.isEmpty` is now `self == UISection()`, so a new key cannot be left out of it; the count checks moved to
  `ConfigurationFile+Counts.swift`.

### Typed facts and readable strings (2026-10-31)

- **An edit's replacement count** is a typed fact, `ToolFacts.replacements`, set by the edit (and by `write` with `old_text`, which
  runs it), never parsed from its sentence. It is recorded with the result in the session file as an optional `replacements` key
  (absent when unknown, so older sessions read as having none), replayed on resume, and kept out of what the model is sent. The
  header shows it on the right, where a read counts its lines: `write · a.txt · exact replacement … 3 replacements · ✓`, singular
  for one. Tests: `ToolFactsTests`, `AgentLoopTests`, `FileToolsTests`, `EditReplacementHeaderTests`; a mutation at each of the
  six handoffs (tool, loop, wire, replay, transcript, composer) turns one red. Probe: `Scripts/probe-output-fold.py`, live and after
  a resume.
- **Multi-line strings in unknown tools' input** (an MCP server's SQL, a job's text) are shown as written, each under its name after
  the JSON of the rest, in the model's order; with nothing else, no empty `{}`. A string in a nested value stays JSON. The session
  keeps the call's own bytes; this is only how it is drawn (`ToolPresentationTests`).

- **The skill tool's header** (2026-10-31) says what the call does: the skill it loads (`pdf`), the words it searches for
  (`search · swift testing`) or `browse` for an empty query, then `· from project, codex` when it narrows its sources. Only the skill
  tool is read this way: another tool with a `name` field keeps its input (`SkillToolHeaderTests`).
- **Sizes in the locale's numbers** (2026-10-31): the decimal mark and the thousands separator are the locale's (`1,5 KiB (1.536 B)`
  in German), `.current` on screen and injected in the tests, which pin `en_US` and `de_DE` (`ToolPresentationTests`).

## Still owed

- Fold choices are not kept across a resume: a resumed session starts from the defaults, as the other folds do. Keeping them needs
  a place for screen state, either an entry in the session file that the loop ignores or a file beside it. That choice applies to
  every fold, so it waits on the owner rather than being made here for one.
