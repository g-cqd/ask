---
status: done
blocked-by: []
date: 2026-10-24
---

# 0057 — The output buffer joins its ends, and cuts inside characters

Found by modelling `OutputBuffer` in Lean (`development/formal/lean/OutputBuffer.lean`) and **confirmed by tests** (`OutputBufferTests`,
`JobFalseFoundTests`, `ClippedTextTests`, four known issues). Two faults, both from keeping the first and last `keeping` bytes of a stream:

- `OutputBuffer.kept` is `head + tail`, with the omitted middle between them removed. `Job.wait(for:)` searches it, so a text that
  straddles the join is reported `found` although the command never printed it. Needs more than 1 MiB of unread output
  (`BashTool.keptBytes` is 512 KiB per end) and a text that lands on the join.
- `OutputBuffer.text` and `Compaction.clipped` cut at a byte, so a character of two or more bytes can be split and the model reads U+FFFD
  where valid UTF-8 was printed.

## Decide

Search the head and the tail as two runs, with the carry the streaming path already keeps, instead of their join. Move each cut to
a scalar boundary, losing at most three bytes of the budget. Remove the four `withKnownIssue` wrappers when the fixes land.

`OutputBuffer(keeping: 0)` traps on `% keeping`; unreachable while the only caller passes a constant, so not fixed here.

## Done (2026-10-24, ADR-0083, diary 2026-10-24 (35) and (36))

- **The join:** `OutputBuffer.contains(_:)` searches the head and the tail as two runs where bytes were omitted, and the stream as one
  where nothing was; `wait` uses it. The real binary answered `found` before and times out now (`Scripts/probe-wait-gap.py`).
- **The cuts:** `UTF8Cut` trims a partial character off a head's end and a tail's start, in `OutputBuffer.text` and
  `Compaction.clipped`, and the omission notes count every byte not shown. A whole stream is now decoded as one.
- The four `withKnownIssue` wrappers are gone. `OutputBuffer(keeping: 0)` is handled in diary 36.
