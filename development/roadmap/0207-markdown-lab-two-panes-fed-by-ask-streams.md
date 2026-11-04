---
status: not-started
blocked-by: []
date: 2026-11-04
---

# 0207 — A Markdown lab: an editing pane and a live render pane, fed by ask's streams

The owner, 2026-11-04: an edit or a stream should land the render instantaneously, the earlier the better; a debug utility with two panes, one for editing and one with the render updating on the fly, to compare; **ask streams its content through it**. This is a development tool, built beside the app in the MarkdownLook sub-package
(bundle identifier `studio.aemi.MarkdownLab`), never shipped. It is where the host probe of 0199 and every latency number of 0203, 0204 and 0206 are measured, in a real window with real input. Design: research note, section 7 (the lab), and the implementation plan.

## What is built

1. **Two panes.** Left: the source, editable, in the system monospaced font, with a gutter showing each top-level block's ordinal, hash and whether it is a clean start (from the block index of 0203). Right: the render, on the viewer host under test (a, b or c of 0199, switchable), at the chosen width, reading size and appearance. Scrolling is synchronised through the source ranges.
2. **The latency HUD**, off by default: per event, the time from arrival (the input event's own timestamp, or the moment a socket read returns) to the end of parse and reconcile, of layout, and of drawing, as microseconds, with a histogram over the last N events (p50, p99); blocks changed of blocks total, cache hits, resident memory, frame times.
3. **The differential check**, on request: after every event a fresh parse is compared with the incrementally edited document (tapes, block index, hashes, diagnostics), and the rendered frames of the changed blocks with a layout from scratch; the first difference is shown and the event trace saved. The live form of 0203's differential test and of the cache-invalidation tests of 0199.
4. **Streams from ask.** A local Unix-domain socket (owner-only permissions), framed bytes: hello with a version, begin (stream id, kind: assistant, thinking, tool, user, and a label), delta, replace (offset, length, bytes), end. The lab appends deltas to the source pane and renders them as they arrive; the person can type into the same text while it streams, which exercises streaming and editing together.
   The default transport is POSIX sockets with one dedicated reader thread (not a dispatch queue); a probe may choose Network.framework on loopback with a token instead.
5. **ask's tap** (a change in ask, off by default, ADR): `debug.markdownTap` names the socket; ask sends the assistant text deltas it already receives, at the point they reach the transcript. **It never changes what ask draws, never blocks** (a bounded queue, non-blocking writes, drops counted and reported in the next frame), costs one flag check when off, allocates nothing when off, and is covered by a test that an absent or full sink changes nothing. ask's own budgets are measured with the tap off and on.
6. **Record and replay.** A capture (the same framing, with arrival times) of a stream or an edit trace; replay at the original timing or as fast as possible. Replays are the deterministic latency tests and the corpus of real streams; captures are written only when asked and never leave the machine.
7. **Edits anywhere, and interleaved.** The person can edit at the start, in the middle or at the end while a stream arrives. A stream's insertion point is a **mark that follows edits** (it moves when text before it changes), so deltas land at the stream's own end wherever the text has moved; a stream's `replace` is relative to the stream's own bytes, and if the person edited inside the stream's region the lab reports the stream as **diverged** and keeps both texts. The HUD shows latency by **position** (start, middle, end of the document, decile series), so a cost that grows toward the start is visible as a slope.
8. **Synthetic typing** through the same path the text view's delegate calls (and real typing, timestamped), so a script can drive the lab and read the HUD's numbers without posting system events.

## Red first, and measured

The framing parser (round trip, truncated frames, oversize lengths refused, unknown types skipped), the queue of ask's tap (never blocks, drops counted), the differential check (a deliberately wrong incremental edit is caught), replay timing (events, not sleeps), the HUD's arithmetic.
Measured with the lab: typing and streaming into documents of 23 KB, 103 KB, 1 MB and 5 MB, and a 100 KB paragraph streamed in 40-byte deltas, on the three hosts, median and p99, quiet machine: the numbers of 0199's probe come from here.

## Done when

The lab opens a file, edits it with a live render beside it, takes a stream from ask with the tap on, shows the latency and the differential check, records and replays; ask's budgets hold with the tap off and with it on; the lab is documented in the sub-package's README.

## Not in scope

Shipping it; a terminal-rows pane (a third view of TerminalKitMarkdown's rows is possible later and not requested); remote streams (the socket is local only); editing history beyond the text view's own undo.
