---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0088 — Active memory is 21.5 MiB against a 20 MiB budget

ADR-0122: the owner set idle 15 MiB and active 20 MiB, assessed on a loaded machine. `Scripts/measure-budgets.py` samples the
resident size right after a `read` tool call is shown. Loaded, 15 runs, release build: idle 12,384 KiB, **active 22,000 KiB** (p95
22,112; min 21,920) against 20,480. The turn adds about 9.6 MiB.

## Plan

1. Separate what the measurement counts. RSS includes shared system libraries; compare it with the physical footprint (`footprint`
   or `vmmap -summary`) before and after the turn, and say which one the budget means.
2. Attribute the growth: `vmmap` at idle and after the turn, diffed by region (malloc zones, stacks, mapped files). Candidates,
   all unmeasured: the first request's connection pool and TLS state, the JSON codec, the session file, transcript and screen
   buffers, the tool run (a thread and a pipe), a read buffer sized for the largest file.
3. Fix the largest first, with a before and after run each. No budget change without the owner.

## Done when

The loaded median is under 20,480 KiB with the fix named in a diary, or the owner moves the limit.

## Measured (2026-10-29, release build, `footprint` and `heap`)

Step 1 of the plan, done. The budget script reads RSS, which counts pages of system libraries that every process maps and that ask
did not allocate. The physical footprint is ask's own cost, and is what Activity Monitor's Memory column shows.

| | RSS | physical footprint |
| --- | --- | --- |
| idle, fresh start | 14.6 MB | 3.6 MB |
| after one turn with a `read` tool | 23.1 MB | 6.6 MB |
| a copy of the owner's biggest session resumed (1,930 responses, 8.9 MB file) | 53.2 MB | 38.8 MB |

A turn adds 3 MB of footprint but 8.4 MB of RSS: the networking and security libraries becoming resident. Against the footprint, both
budgets hold by a factor of three. **Owner decision needed: which one does the 15 and 20 MiB budget mean?** Recommended: the footprint,
plus a new budget for what a long session costs.

What a long session holds (`heap`, 23.8 MB allocated of the 38.8): Swift strings 12 MB (32,000 of them); one array of the whole
transcript's wrapped screen lines, `[ScreenComposer.Line]`, 3.1 MB; two retained arrays of the opening `ConversationUpdate`s, 1.7 MB,
which nothing needs once the screen is open; the session's entries 0.8 MB; file-path strings from the project index 0.8 MB.

## Plan from here

1. Free the opening updates after the screen has applied them (about 1.7 MB, no behaviour change).
2. The owner's idea, a screen that does not keep the whole conversation laid out: keep per-item line counts for scrolling and build the
   wrapped lines of the visible window and a margin, not of every item. Saves the 3 MB array and the strings inside it (the strings are
   most of the 12 MB; attribute them by item kind first).
3. Let the session tree keep large tool results and responses on disk, read back when an item is opened or the context is built.
4. Re-measure each with the footprint and the long session; add the long-session figure to `Scripts/measure-budgets.py`.

## Owner's decision (2026-10-29)

The budget is **resident size**: 15 MiB idle and 20 MiB active mean RSS, so the budget as written stands and the active figure
(22 to 23 MiB) is still over it. The physical-footprint figures above are information, not the budget. Improvement opportunities are to be
studied for feasibility and built when relevant, as long as they do not worsen another metric significantly (cold start 50 ms, input
4 ms, action 8 ms, idle 15 MiB). The 8.4 MB that a turn adds to RSS is mostly the networking and security libraries becoming resident; the
first feasibility question is what in the first request touches them (URLSession and its TLS state, certificate evaluation, the JSON
codec) and whether a lighter path exists on the first request, measured as RSS against first-request latency.

## Feasibility study of the resident-size budget (2026-10-29)

Rule from the owner: the budget is RSS. Idle is 14.6 MiB (budget 15), active after a tool turn 22 to 23 MiB (budget 20).

**Where a turn's 8.4 MiB comes from** (`vmmap -summary` before and after a tool turn): code pages of the system libraries paged in by the
first request (`__TEXT` +4.0 MiB), malloc (+2.0 MiB), mapped files, constants. It is a property of the first request, not of the turn.

**Experiment** (`/tmp/rss`, throwaway): one HTTPS request to the same host, RSS before and after, three runs each.

| client | RSS added by the first request | time |
| --- | --- | --- |
| `URLSession` (what ask uses) | +9.1 MiB | 0.51 s |
| `NWConnection` with TLS, HTTP/1.1 written by hand | +5.7 MiB | 0.51 s |

A 3.4 MiB saving at the same latency would bring the active figure to about 19.5 MiB, under the budget, with cold start and idle
untouched (the transport is created on first use, as `URLSessionTransport` is). So this is relevant. It would be a second conformer of
the existing `HTTPTransport` seam in AskAI; `g-cqd/HTTP` is an origin-server library and gives no client codec, so the client side
(request writer, response parser: status line, headers, `Content-Length`, chunked, close-delimited; streaming bodies; cancellation;
keep-alive pooling so a session does not pay a handshake per turn; plain TCP for localhost) is ours to write, about 400 lines plus tests.
Risks to settle before building: the system proxy settings `URLSession` applies and a raw `NWConnection` does not (read them from
SystemConfiguration, or fall back to `URLSession` when a proxy is configured, which must not itself load CFNetwork on the common path);
certificate and error mapping to `HTTPTransportError`; the MCP HTTP transport shares `HTTPTransport`, so it gets the saving too.
Decision for the owner: build it (about a session), keeping `URLSession` as the fallback.

**Step 1 (opening updates), done:** `history` and `opening` are `consuming` and consumed, so the two arrays of the opening updates are no
longer held for the screen's lifetime: live heap of the 1,930-response session 23.8 to 22.6 MB. Resident size did not move (53 to 55 MB,
noise): malloc keeps freed pages. Lesson recorded: trimming the heap does not lower RSS; only touching fewer pages does, so the windowed
transcript (step 2) lowers RSS only if the lines are never built, and the lazy line building has to be measured as RSS, not as heap.

## Owner's decision (2026-10-29)

Not today: ask will not write its own HTTP request handling now. The `URLSession` transport stays; the `NWConnection` study above is the
record of what building it would save (about 3.4 MiB resident) and what it would cost. Active memory remains over its budget until a
different way is found or the owner revisits this.

## Step 2, first half (2026-10-29): the transcript keeps heights, and lines near the window only

TerminalKit 0023's `WindowedLayout` replaces `LayoutCache` in `ScreenComposer`: every item's row count is kept, and the wrapped lines of
the items within two windows of the shown rows; the per-item hard lines held for the selection highlight are gone (the highlight only
resolves which items a selection names, `ShownTranscriptContent` reads lines on demand). `Scripts/measure-long-session.py` measures it:
release build, a copy of the owner's 12 MB session (5,564 entries), 120x40, against the previous binary run interleaved on a loaded machine.

| | before | after |
| --- | --- | --- |
| resident size, open and quiet | 61.2 MiB | 54.9 MiB |
| open (spawn to the quiet first frame) | 545-664 ms | 504-636 ms |
| a new width, 120 to 100 columns | 302-354 ms | 225-254 ms |
| a typed byte | under 1 ms | under 1 ms |
| fresh screen, resident size | 14.3 MiB | 14.3 MiB |

Every item is still laid out once to learn its height, so opening and a new width cost a full layout. Laying out only the last 50 items
bounds what is left to gain here: 52.6 MiB and 258 ms to open. Next: heights found from the end on demand.

## Step 2, second half (2026-10-29): laid out from the end, on demand (TerminalKit e2607ad, 0023 done)

The transcript is laid out from its end as far as the shown rows and a window above them need, and further as the reader scrolls up, so
opening a session and taking a new width cost the screen, not the conversation. Paged to the top, the screen equals the full layout's, with
the same 16,148 rows below it, and the first prompt shown.

Two fixes the measurement found. **Page Up did not scroll before a mouse event**, in every build: `ScreenSession` loaded the newest frame's
geometry for mouse events only, so a key's scroll was clamped against an empty frame until the wheel or a tick had loaded one. Every input
now loads it. (The first half's Page Up figure above timed frames that did not move, and is struck.) And a folded block's header counted
its output's lines by splitting the whole output after a tab replacement; `TranscriptContent.hardLineCount(of:)` counts line feeds.

Release build, the same 12 MB copy, interleaved against the full layout (the first half's parent with the Page Up fix), 2 x 3 runs:

| | full layout | from the end |
| --- | --- | --- |
| resident size, open and quiet | 60.9 MiB | 52.7 MiB |
| open | 439-442 ms | 229-230 ms |
| a new width, 30 pages up | 231 ms | 15-18 ms |
| a typed byte | 1.0-1.3 ms | 0.9-1.3 ms |
| Page Up, median of 30 (worst) | 1.3 ms (1.5-1.9) | 2.5 ms (3.5-5.9) |
| fresh screen, resident size; open | 14.3 MiB; ~35 ms | 14.3 MiB; ~35 ms |

Page Up is 1.2 ms dearer, inside the 4 ms input budget: it lays out the page it reaches, which the full layout paid for at open. What is
left of the 52.7 MiB is the session itself (its strings, about 16 MB in 38,000 string buffers, and the entries): step 3's lever.

## Step 3, first part (2026-10-29): the session file is read a chunk at a time

What the 52.7 MiB of the open 12 MB session is (`heap`, `vmmap`, `footprint`): live heap 19.1 MB (Swift strings 12.4 MB in 18,676; tool
call inputs as bytes 2.5 MB; the entry array 1.5 MB; the transcript's items 0.4 MB), and **11.5 MiB of "Malloc Large (empty)"**: the
buffer the whole file had been read into, freed after the open and still resident, because macOS reclaims large frees lazily. Paging up
later let malloc return it (RSS 53.6 to 42.3 MiB in one run), which is why the figure moved between measurements.

`SessionLogReader` reads 64 KB at a time into one reused buffer and recovers line by line (`SessionLogRecovery`, moved out of `SessionLog`);
a line that spans chunks is gathered, one past the line limit is dropped as it arrives. Tests: 60 random damaged logs at 9 chunk sizes
recover exactly what the whole-file reader recovers; a file read through a descriptor in 5-byte chunks; an empty file.

| 12 MB session, release, interleaved, load average 6 to 9 | before | after |
| --- | --- | --- |
| resident size, open and quiet (3 x 3 runs) | 53.2-53.9 MiB | 41.5-43.8 MiB |
| physical footprint, and its peak | 42 MB, 42 MB | 29 MB, 29 MB |
| open, in process (`session/open 1000 entries`, p50) | 2.46 ms | 2.49 ms |
| open, whole program | 250-500 ms | 270-680 ms (load; minimums 222 and 234) |

Next in step 3: the payloads themselves. Of the file's 12 MB, responses are 7.1 MB (thinking signatures 3.6, tool call inputs 2.5, text
0.25) and tool results 4.6 MB; the session has 22 compactions, so only what follows the last one is ever sent again. Keeping the entries
before it as file offsets, read back when shown, opened or forked, is the lever on the 12.4 MB of strings.

## Step 3, second part: payloads on disk (designed, not built)

**What it would save.** On the 12 MB session, 5,465 of the leaf path's 5,564 entries precede its last compaction, and with them 98% of the
payload bytes: signatures 3.56 MB, tool call inputs 2.25 MB, tool results 3.96 MB (after it: 0.13 MB in all). `malloc_history` attributes
the live strings to the decoded payloads, each held once: the screen's items share their storage, and the `content + lostNote` copy in
`WirePayload` costs nothing in the end (tried and measured: live heap +0.1 MB, reverted). So the strings go only if the payloads do.

**Who reads payloads** (26 sites): the request context and compaction (only the entries after the last compaction on the path), the
screen's replay (`SessionReplay`: the text of tool results and answers, not signatures or tool inputs), the outline and summary (user text),
and the writers: `fork`, and `SessionLog.snapshot` when a file is rewritten.

**The risk.** A writer that copies a slimmed entry loses its signatures or tool inputs from the new file, silently; a context rebuilt after
a `/tree` checkout to before a compaction would send thinking without signatures (a 400 from Anthropic) or tool calls without input.

**Design, so the compiler finds every reader.** An entry read from the file keeps where its line is (offset and length; the log is append
only, so they do not move). Entries before the leaf path's last compaction are kept slim: signatures and tool inputs dropped, tool result
text kept to its first lines and its line count. `SessionEntry.payload` stays the full payload type but is reachable only through
`SessionFile.payload(of:)`, which reads a slim entry's line back (`pread`, decode, verify its id); the slim form is a separate type that
the screen's replay accepts and the context builder and the writers do not, so a missed site does not compile. Moving the leaf or the
last compaction re-reads what becomes context. Tests: fork and rewrite of a session with slim entries are byte-identical to the original's
records; a checkout to before a compaction builds the same request as with everything in memory; a file changed under ask (the lock
prevents another ask; an editor can still) is detected by the id check and falls back to the slim text with a notice.

**Expected:** about 9 of the 11.3 MB of strings for this session, and an open that decodes less. Cost: one `pread` and decode when a folded
old tool result is opened (under 1 ms for the largest, 1 MB line limit) or when the leaf moves to before a compaction. About a session of
work; the owner's go-ahead is the remaining step.


## Owner decision (2026-10-29, payloads on disk)

Proceed **only if it does not introduce lag when session screens load**. Opening/resuming, paging to old blocks, expanding them, checkout,
fork and resize must be measured against the current implementation. The source-design estimates above are not measured guarantees;
use a bounded cache or revise the design if synchronous disk reads move input/action or screen-loading latency significantly.

## Owner decision (2026-10-30, evening): deferred

"I'd delay that way further down the pipe, we are much more efficient than any harness right now, let's focus on other topics." Step 3
(payloads on disk) is parked with the later entries; active memory stays at 21.5 MiB against the 20 MiB budget until it is picked up.

## Measured again (2026-10-30, night)

`measure-budgets.py`, 12 runs each under full load, the build of the morning (`83ed86b`) and the evening's: idle memory 15.3 MiB then,
15.9 MiB now (+0.6 MiB from the day's features), active 23.7 then 24.1 MiB; both over their budgets (15 and 20). Cold start and input
delay move with the load (22 ms and 0.3 ms in quiet rounds, 77 to 82 ms and 10 ms under full load) and did not change between the builds.

