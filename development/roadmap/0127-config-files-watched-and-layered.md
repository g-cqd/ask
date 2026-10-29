---
status: not-started
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
