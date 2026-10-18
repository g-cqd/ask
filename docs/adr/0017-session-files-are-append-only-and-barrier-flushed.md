---
status: accepted
date: 2026-10-18
---

# 0017 — Session files are append-only, barrier-flushed, and never lose a damaged original

## Context

ADR-0013 made damaged sessions load by default and forbade loading from writing. The file store still had
to decide three things: how a change reaches disk, what happens on the first write after a damaged load,
and what a write failure leaves behind.

## Probes

**Flush semantics**, from the man pages. fsync(2) on Darwin: the drive "may also re-order the data so that
later writes may be present, while earlier writes are not", and calls this "not a theoretical edge case".
fcntl(2): `F_BARRIERFSYNC` is fsync plus a barrier that orders earlier flushed writes before later ones.
`F_FULLFSYNC` drains the drive's cache before returning.

**Cost**, measured through `SessionFile` (release build, package-benchmark, 484-byte records):

| Level | p50 | p99 |
|---|---|---|
| none | 9 µs | 20 µs |
| fsync | 28 µs | 39 µs |
| barrier | 190–325 µs | 0.5–1.1 ms (max 1–5.8 ms) |
| full | 2.75 ms | 3.7 ms |

**Scaling.** The first version applied each change to a copy of the tree, which cost 181 µs at 10,000
entries and 1.86 ms at 100,000. In-place changes with a checkpoint rewind cost 8–11 µs at every size.

## Decision

1. **One complete record per change, flushed before the change counts.** A change that cannot be
   persisted is rewound; memory never runs ahead of the file.
2. **Default durability is the barrier**, using AemiIO's `DurabilityProfile` and `PosixFile.sync`, which
   falls back to fsync when a filesystem refuses the barrier. With ordering, a crash leaves a prefix and at
   most a torn tail, which is exactly the damage recovery repairs without loss. With plain fsync, a mid-log
   hole or an empty renamed file are documented outcomes. `.full` is opt-in, since its median alone exceeds
   the 2 ms action budget.
3. **The first change after a damaged load, or after a failed append, rewrites.** A snapshot is written
   beside the file, the original is hard-linked to `<name>.damaged[-n]`, then the snapshot is renamed in.
   A complete session file exists at every instant, and damaged bytes are never discarded or appended to.
4. **Create and fork never overwrite** (`O_EXCL`).

## Consequences

- Persistence costs up to about 1 ms at p99 per turn, with rare multi-millisecond tails. It belongs on a
  turn boundary, never on the input path; the agent loop (roadmap 0009) must keep it there.
- Holding a copy of `SessionFile.tree` across a change makes that change copy the tree. This is documented
  on the API; callers read the tree when they need it.
- Not yet decided: where session files live, and what happens when two processes open one session. Until
  locking exists, a second writer is the user's responsibility.
