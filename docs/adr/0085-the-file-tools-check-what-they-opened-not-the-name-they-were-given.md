---
status: accepted
date: 2026-10-24
---

# 0085 — The file tools check what they opened, not the name they were given

## Context

`read`, `write` and `edit` ask the sandbox about a path, resolve it to its canonical form, and use that path by name (ADR-0035). The
canonical path narrows what a link swapped in afterwards can do, but it is still looked up twice, once to check and once to use, and
ADR-0035 said so: "a link swapped in between could still redirect a write". `bash` is not exposed (Seatbelt checks at the operation),
but the file tools are checked in process, and a job the sandbox lets write in the workspace can rename a directory away and put a link
to a protected one in its place, in a loop, while the model calls a file tool.

Measured, before any change: a racing job and 6,000 writes of `d/pwn.txt` landed 2 files in ask's configuration directory (in two of
three runs), where `credentials.json` and `config.json` live; `config.json` is how a sandbox is widened. A read could be redirected the
same way, and a deterministic test that swapped the directory at exactly that moment read the protected credentials file.

## Decision

1. **Under a restricted policy, the object is checked where it really is.** A read opens the file (`O_NOFOLLOW`), asks the kernel where
   the descriptor is (`F_GETPATH`), authorizes that real path for reading, and reads from the descriptor: the name is never looked up
   again. The size, the type and the contents come from the same descriptor.
2. **A write works relative to a verified directory.** The deepest existing directory is opened and its real location authorized for
   writing; each missing directory is made with `mkdirat` and entered with `openat` (`O_NOFOLLOW`), authorized before it is made; the
   file is written to a temporary name in that directory and renamed over its target with `renameat`, keeping the permissions of what
   it replaces. No step looks a directory up by name again, and the final name is authorized with the directory's real path in front of
   it, so a protected file in an allowed directory stays protected.
3. **With nothing restricted, nothing changes.** An unrestricted policy has nothing to redirect around; the old code runs and is
   untouched.
4. **Where `O_NOFOLLOW` is a second line.** The guarantee is the check on the descriptor; `O_NOFOLLOW` only makes a replaced
   directory fail with a clearer message before the check does. A write whose final name has become a link replaces the link, not
   its target.

## What this does not close

Hard links (a hard link in the workspace to a protected file would be written through; making one needs the sandboxed job to look
the protected file up, which Seatbelt denies); a file tool racing another file tool; and `bash`, which is checked by the kernel and
was never exposed. The edit tool reads and writes in two verified steps; the file can change between them, which is not an escape.

## Consequences

A few more system calls per file tool call under a restricted policy (the default). The write path is a second implementation of
"atomic write keeping permissions", which Foundation's was; a test pins the permissions, the created directories and that no
temporary file is left behind.

## Probes

Deterministic tests that swap the directory at the vulnerable instant (a hook between the check and the use), for a read, a write,
a write that creates directories, a target that is readable but not writable, and a protected file inside an allowed directory; a stress test
with a racing thread; fourteen compiling mutants. The measurement above is the control. Real binary: not probed, see diary 2026-10-24 (38).
