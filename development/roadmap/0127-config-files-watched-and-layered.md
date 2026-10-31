---
status: done
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

## Built (2026-10-29): watching, through AemiIO

The owner chose to promote both kinds of watcher into AemiIO and use them in ask and Atelier. Done: aemi `dcad319`
(ADR 0016: `FileWatching`, `FileWatcher` from Atelier, a new `KqueueWatcher`, `DirectoryWatch`, `FileIdentity`,
`CanonicalPath`, 59 tests); the pins moved through AemiJSON `8db07fb`, AemiMarkdown `ece0313`, TerminalKit `30b0fcc`;
Atelier `1694d51` uses AemiIO's watcher (its ADR 0004); ask watches its configuration and executable with one
`KqueueWatcher` and applies configuration changes while idle (ADR-0131, with the measurements).

Still owed here: what replacing versus adding does per section today (lists such as `mcp` servers and sandbox paths),
and the setting that makes a layer replace, and its name.

## Layering per section, and masks for MCP servers (2026-10-31)

What a later file does to an earlier one today. The real ladder is two files, your own, then the trusted project's
`.ask/config.json`; the environment and flags come after them.

- **Scalars** (top level, `ui`, `skills.enabled`, `environment.shell`, and the like) are masked key by key: a layer replaces only
  the keys it sets.
- **Lists that protect add up.** `sandbox.hide` (`denyRead`) and `environment.withhold` keep every layer's entries.
- **Scopes only narrow.** `sandbox.write` and `sandbox.read` are intersected over the layers, and `network` takes the lowest; only
  flags widen them.
- **Replaced, but from your own file only.** `skills.sources`, `skills.maxListed`, `sandbox.readable` and `sandbox.writable`,
  `environment.pass`, and `approvals`. A project's file cannot set them, so no layer above your file ever replaces them.
- **`mcp` goes by server name.** A server a later file defines in full replaces yours of that name, and the others are kept.

The gap was MCP: a project could not turn off one of your servers, because `{"mcp": {"xcode": {"enabled": false}}}` was refused
with `needs a "command" or a "url"`. It is fixed now. In a project's file, an entry with no `command` and no `url` is a mask
(`MCPServerMask`). It changes the server of that name in your file, and may set only `enabled`, `tools`, `mode` and
`maxDirectTools`.

- It refuses `args`, `env`, `cwd` and `headers`. Otherwise a repository could hand your server, with the secrets you gave it, other
  arguments, a different directory, or variables of its own.
- A mask naming no lower server is ignored, with a notice.
- In your own file, the lowest layer, such an entry is still refused.
- `ask trust` lists what each mask changes.

Tests: `MCPServerMaskTests`, written first; 4 of the 6 failed before the change. Docs: `configuration.md` ("Where a value comes
from", `mcp`) and `skills-and-mcp.md`.

**The "replace instead of add" setting is not built, and is for the owner.** No section is replaced across the real ladder any
more: what a project may set adds, narrows or masks. A replace switch could only:

- widen: drop the user's withheld variables or hidden paths, or reopen the write scope;
- drop the user's MCP servers wholesale, which masks now do one server at a time, and visibly.

Both would let a repository undo a protection in the user's file. Unless the owner names a case that needs it, this entry is done
without it.
