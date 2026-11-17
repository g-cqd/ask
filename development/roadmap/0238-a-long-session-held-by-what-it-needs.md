---
status: in-progress
blocked-by: []
date: 2026-11-15
---

# 0238 — A long session's memory follows what it needs, not what its file holds

From the owner's review of the running processes (`family/REVIEW-2026-11-15-performance-memory-settings.md`, section 4.1): a
fresh ask is 29 MB; two resumed on long sessions were 191 and 199 MB, with peaks of 280 and 298 MB at resume. The owner chose
(2026-11-15): the small part now, the rest probed and designed before any code.

## Measured (diary 2026-11-15-12), on a copy of the 81 MB session

| What | Probe | Result |
|---|---|---|
| The session, opened | footprint before and after `SessionFile.open` | 8 → 116 MB: every entry decoded, 35,297 of them (16,923 responses, 17,815 tool results, 472 prompts, 72 compactions) |
| What a request can still use | the active branch from the last compaction on | 1,070 of its 35,041 entries; about 6 MiB of the 122 MiB the branch's payloads describe |
| The conversation shown again | `history()` into a `ScreenController` | 55,051 updates, +38 MB while they are made; 29,994 blocks, +10 MB; 52 MB given back when the screen is released, none when the updates are |
| The search index | built from the session; then read again from its file | built in 1.25 s with a peak of +309 MB; its file is 70 MB; 62 MB once read, in 0.14 s; a search in it 3.7 ms |

## Step 1: done (2026-11-15)

The search index is let go once it is in its file, and read again by the next search or update (0.14 s for this session). One that
could not be written is the only copy and stays. An index whose file was lost is now written again (it was not, while held).

## Steps 2 and 3: done for a plain session (2026-11-17, ADR-0165, diary 2026-11-17-02)

The tree leaves the payloads nothing reads in the session file, read back at an offset when asked; the screen shows the
conversation since the last compaction's first kept entry, with a line saying what is left out. On the owner's session: resumed
resident size 210 to 60 MiB, open 790 to 500 ms. What was proposed below is kept as it was written; the three points "to settle
before step 2" were answered by probe, not by the owner: the readers of `entries` that need a payload are the replay, the search
index, a fork and a rewrite, and each now reads it; a rewind's menu needs only prompts, which stay held; and a cold payload in a
compressed file was not measured, since those sessions are held whole.

Open: a compressed or encrypted session (a frame is not read at an offset), step 4's peaks, loading the earlier part on scrolling
to the top.

## Proposed, not decided: steps 2 to 4 (as first written)

**2. The tree holds payloads for what a request can use, and where the rest is.** Entries off the active branch, and before the
last compaction's first kept entry, keep their id, their parent, their kind and where their record is; the payload is read when
something asks: a rewind or a branch switch, a fork, the search index, the screen showing them again. About 100 MB of the 116
here.

What stands in the way, found by reading:

- **A compressed session cannot be read at an offset** (ADR-0138): it is one deflate stream, flushed after each record, started
  again only when the file is reopened. A record's payload is reached by inflating from the last restart before it. So "where
  the rest is" is an offset for a plain file, and a restart point plus a distance for a compressed one; or the cold payloads go
  to a scratch file ask maps, outside its heap.
- **`SessionTree` is a value with `entries: [SessionEntry]` in its public face**, read in 31 places of 22 files. An entry whose
  payload may be absent changes that face; which of the 31 need a payload was not sorted.
- **A file rewritten** (`/encrypt`, a repair) moves every record.

**3. The screen shows the end of a resumed conversation, and the rest when it is scrolled to.** Today every block is made again
(55,051 updates for this one), which is also why resume and `/reload` are slow on long sessions (note n47). A decision for the
owner, since it changes what is seen: everything as today, or the conversation since a bound (the last compactions, a number
of blocks) with the earlier part loaded on demand.

**4. The peaks.** The resume peak (280 to 298 MB) and the index's build peak (+309 MB) are made of what is decoded on the way
and freed after; 30 MB of freed memory is not returned. Decoding in a stream rather than whole, and an index that does not hold
every document's text (its file is as large as the session), are the candidates.

## To settle before step 2

- Which of the 31 readers of `entries` need a payload, and how often each runs: decides the shape of the accessor.
- What a rewind or a branch picker shows of an old entry: if it is the prompts (472 here), they can stay in memory.
- The cost of reaching one cold payload in a compressed file, measured: decides between "inflate from the last restart" and a
  scratch file.

## Done when

A resumed long session costs memory in proportion to what a request and the screen use, the review's two processes measured
again, and resume no faster only by accident: its time recorded before and after.
