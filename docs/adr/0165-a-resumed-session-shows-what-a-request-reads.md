---
status: accepted
date: 2026-11-17
---

# 0165 — A resumed session shows what a request reads, and leaves the rest in its file

## Context

The owner's review of 2026-11-15 (`family/REVIEW-2026-11-15-performance-memory-settings.md`, section 4.1) found two resumed asks at
191 and 199 MB where a fresh one is 29, and roadmap 0238 measured where it goes in an 81 MB session of 35,297 entries: the tree
holds every payload (8 to 116 MB), and the screen is shown every entry again (55,051 updates, 29,994 blocks), which is also why
resume and `/reload` are slow on long sessions (note n47). Step 1 (the search index) was done. Steps 2 and 3 were proposed and
waited for the owner, whose word on 2026-11-17 was to continue the roadmap and the review's findings.

## What was tried first, and refuted

| Claim | Probe | Verdict |
|---|---|---|
| Entries nothing reads can be held deflated in memory | `ColdProbeTests` (throwaway), a copy of the owner's 85 MB session, footprint by `task_info`: each entry's record line deflated at level 1 when it was decoded, the warm ones inflated at the end | **Refuted**: 124 to 106 MB, and the open 0.35 to 1.30 s. Half the text is thinking signatures, which deflate to 0.7; and the freed decode garbage stays in the heap |
| The same, packing the entry after the open | The same, in a second pass | **Refuted**: 122 to 149 MB; the compressed copies are allocated among the freed payloads |

## Decision

1. **A plain session's entries whose payload nothing reads stay in the file.** Opening decodes every line as it always did, so
   damage is found and said exactly as before; then, for a response, a tool result or an assistant message of 512 bytes or more
   that names no picture, the entry keeps its id, its parent, its kind and where its line is (`ColdLine`), and the decoded payload
   is let go. `entry.payload` reads the line again, at an offset, through a descriptor `ColdSource` opens for itself.
2. **Held are**: the active branch from the last compaction's first kept entry on (the whole branch without a compaction),
   decided once the file is read; every prompt (a branch picker lists them); every compaction and destination; anything with a
   picture; anything shorter than 512 bytes.
3. **`ColdSource` has its own descriptor, not the session lock's.** The lock is an `flock`; a duplicated descriptor shares it, and
   an entry copied out of the session would hold the session locked after it closed (the defect of 2026-11-13).
4. **A rewrite reads everything first and leaves none in the file** (`holdAll`): the file is about to be replaced. A payload the
   file no longer has makes the rewrite, and any snapshot or fork, fail with nothing written. `payload` shows a note in its
   place, `readablePayload` says nil, and that note is never written as the entry.
5. **A session that was migrated, a framed one (compressed or encrypted) and one opened to list or check it are held whole**:
   a migration changes what a line says, a frame is not read at an offset (ADR-0138), and a listing reads once.
6. **The screen shows the conversation since the last compaction's first kept entry**, with a line saying how many earlier
   entries there are and that `/search` and `/rewind` reach them (`SessionTree.sinceLastCompaction`). `/rewind` to an earlier
   prompt shows that branch's conversation since *its* last compaction. A session never compacted is shown whole.
7. **A client of `ask serve` is sent the whole** (`history(whole: true)`): what it is told it has is not for ask to cut.

Point 6 is the change a person sees; it was the owner's to decide (roadmap 0238, step 3) and is taken here on their word to continue,
with the default of the line above. Not built, and the owner's to ask for: loading the earlier part when the screen is scrolled to
its top, and a setting for showing it whole.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| The tree no longer holds the payloads nothing reads | A copy of the 85 MB session opened in a release test, footprint by `task_info` | **Holds**: 124 to 54 MB; 20,820 of 37,873 entries left in the file |
| What is read back is what the file said | Every payload and the snapshot bytes of the tree against one decoded whole | **Holds**: 0 of 37,873 differ; the snapshots are byte-identical |
| Resume | `Scripts/measure-long-session.py`, the same session, 5 runs, main's build against this, alternated | **Holds**: open 790 to 500 ms, resident 210 to 60 MiB (median), after 5 pages 210 to 60 |
| The tree alone is enough | The same with the replay unchanged | **Refuted**: 210 to 205 MiB, open 790 to 1,510 ms: the replay read every entry back and the screen kept them. Both halves are needed |
| Reading one payload back is cheap | Every payload of the session read in a loop | 0.23 s for 37,873; a scan of kinds 6 ms |
| Open costs little more | `SessionFile.open` alone | 0.36 to 0.44 s: the scan for pictures and the warm set |
| Damage is found when the file is opened | `SessionInFileTests`: a line cut short and an orphan among large entries, against the same file read whole | **Holds**: the same issues, ids, parents and payloads |
| Offsets hold whatever the chunks | The same session read in chunks of 1, 7, 100, 4,096 bytes and 1 MiB | **Holds** |

## Consequences

- A person sees less after a resume of a long session, and is told so. The screen's blocks, the replay's steps and the tree's
  payloads were each most of 150 MB; the third was only the smaller part.
- **The tree's history is not in memory: a file changed under an open session loses it.** A session is locked by one writer, and
  ask never rewrites a plain session in place, so what changes it is the person (an editor, `truncate`). The entries then read as
  a note, and nothing is rewritten from them.
- Reading every payload (the search index's build, a fork, the replay of a rewound branch) costs a read and a decode each, 0.23 s
  for this session, where it cost a field access.
- Not done: the peaks at resume and at the index's build (step 4), a compressed or encrypted session (held whole as before),
  and the entries a live session appends after the last compaction, which are held until the next open.
- **Not known: the screen's memory for a session with many compactions and a long tail since the last.** The owner's session
  keeps 1,070 entries; one that kept 30,000 would show them all.
