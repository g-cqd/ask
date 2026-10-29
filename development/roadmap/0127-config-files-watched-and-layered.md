---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0127 — Configuration files are watched, and each layer adds to the ones above it

Owner wish (2026-10-28 23:02): when the sandbox allows it, watch every configuration file ask reads (the "ladder": user, project, and
any others) and apply a change while ask runs. A file lower in the ladder does not replace one above it; it adds to it and masks only
the keys it sets, unless a setting says otherwise.

## Still owed

- Today the files are read again before each prompt (ADR-0031); find what replacing versus layering does per section now (sections are
  layered key by key; check lists such as `mcp` servers and sandbox paths).
- Watching through FSEvents or a dispatch source (a system API, white paper rule), only for files the sandbox lets ask read.
- The setting that makes a layer replace instead of add, and its name.

## Priority reaffirmed by the owner (2026-10-29)

Automatic configuration update when files change is important: move this out of the low-priority infrastructure group, directly after the
urgent Claude investigation and immediate correctness fixes. Preserve layered configuration and sandbox rules; invalid updates keep the
last valid configuration and report why. Watch rename/replace saves as well as in-place writes, without resetting a draft or an active turn.

## What the documentation and the existing code say (2026-10-29)

Through apple-docs (7 calls, all answered, 14.7 s, 41k tokens): `dispatch/dispatchsource/makefilesystemobjectsource(filedescriptor:eventmask:queue:)`
with `dispatch/dispatchsource/filesystemevent` (`.write`, `.rename`, `.delete`, `.attrib`), and `coreservices/1443980-fseventstreamcreate`
(macOS 10.5). The model recommended a descriptor on the file; that is wrong for this use: after an editor's atomic save the descriptor still
names the old, renamed-away inode, and later writes go unseen. Watch the **parent directory** and compare the file, or use FSEvents.

ask already does the first for its own binary: `BinaryWatcher` keeps a kqueue on the executable's directory on a 64 KiB thread of its own,
because the linker swaps files (ADR-0033). Atelier has the second as a general watcher (`AtelierFileTree/AtelierFileWatcher.swift`, below);
whichever is used, configuration files get one watcher for all their directories, not one per file.

## Atelier's watcher, and promoting it to Aemi (2026-10-29)

`g-cqd/Atelier` at `2af1c51`, `Packages/AtelierCore/Sources/AtelierFileTree/AtelierFileWatcher.swift` (572 lines, 386 of tests): an actor
`FileWatcher` over **one FSEvents stream** for every watched directory and every watched file's parent directory.

- A file watch follows the **path**, not the inode, so it survives atomic saves, and the file need not exist yet.
- Paths keyed by `realpath(3)` (`/tmp` arrives as `/private/tmp`), symlinked files under both spellings.
- Changing the watched set restarts the stream from the last event id, so nothing in between is lost.
- A coalesced or dropped batch (`MustScanSubDirs`) is reported as a change to everything watched below it; a full buffer (1,024 events)
  does the same, so a slow reader rescans rather than misses.
- `suppressNotifications(for:)` mutes a path for a second after the app wrote it itself; at most 8 excluded directories.
- Only Foundation, Synchronization and os: nothing Atelier-specific. Its test suite comes along (`FileWatcherTests.swift`).

KittyCode (`Apps/KittyCode`) already uses it for exactly this entry's job: `WatchedFileMonitor` reloads its configuration "after every save,
another editor's atomic ones included". `AtelierProcess/HardenedProcessRunner`'s kqueue reads a child's pipes; it watches no files.

**Cost, measured** (release builds, two directories watched, one atomic save, three identical runs each): a Foundation program idles at
5,840 KiB with one thread; FSEvents adds 176 KiB and one queue thread and reported the save once; a kqueue on the two directories adds 64 KiB
and one thread and reported it twice. Both are far inside ask's idle budget (15 MiB, 14.5 used).

**Proposal.** Promote `FileWatcher` (without KittyCode's main-actor monitor) to aemi, in `AemiIO` or a small `AemiFileWatch` library, and
use it here: one watcher over the configuration ladder's directories (user `~/.config/ask`, the project's, any `XDG_CONFIG_HOME`), each event
a reason to call `refreshSettings` while idle, never during a turn or over a draft. `BinaryWatcher` could then move to it too, leaving ask
one watching primitive. The cost of the promotion: ask, TerminalKit, AemiJSON and Atelier all pin aemi at `f6da05c`, and SwiftPM allows one
revision per package in a graph, so the new revision is adopted by all four together. Waiting for the owner's choice of home and timing;
until then 0127 can be built on a directory kqueue like `BinaryWatcher`, behind the same small interface, and switched later.
