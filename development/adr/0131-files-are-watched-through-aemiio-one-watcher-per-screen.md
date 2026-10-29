---
status: accepted
date: 2026-10-29
---

# 0131 — Files are watched through AemiIO, one watcher per screen, and configuration applies while idle

## Context

Roadmap 0127: the configuration files should apply when they change, not only before the next prompt (ADR-0031). ask
already watched one file, its own executable (ADR-0033), with a kqueue on the directory (`DirectoryWatch`,
`BinaryWatcher`). Atelier had an FSEvents watcher. The owner asked for both to become one reusable surface in aemi's
AemiIO and for both apps to use it: aemi ADR 0016 (`FileWatching`, `FileWatcher` over FSEvents, `KqueueWatcher`,
`DirectoryWatch`, `FileIdentity`, `CanonicalPath`), Atelier ADR 0004.

## Decision

1. **ask's copies go.** `DirectoryWatch` is AemiIO's (`FileWait` keeps using it for one-off waits); the executable and
   the configuration are watched by AemiIO's `KqueueWatcher`, which follows each file by path, sees atomic saves and
   writes in place, and anchors a file under a missing directory on the nearest one that exists.
   kqueue rather than FSEvents: five files, no coalescing delay, every platform.
2. **One watcher per screen.** `FileChangeSignal` reports the watched paths that changed in each burst, after 150 ms of
   quiet; `AgentConversation.watchFiles` routes them: the executable to `BinaryWatcher` (now only the identity check,
   announcing the first new build once), the configuration files to a reload. A second watcher cost one thread and
   0.2 MiB at idle (measured below), so the two share one.
3. **Configuration applies while idle.** The watched files: `~/.config/ask/config.json`, `trusted.json`,
   `providers.json`, and `<project>/.ask/config.json`. Between turns a change is read at once (`refreshSettings`, the
   same all-or-nothing read as before each prompt, reporting changes as details and a broken file as a notice), and new
   or changed MCP servers start then. During a turn it is noted and applied when the turn ends, since the running loop
   keeps the settings it started with. The draft is never touched.

## Measured (2026-10-29, release, loaded machine)

- Cold start to the first prompt frame, 30 alternating runs: median 18.6 ms before, 18.5 after.
- Idle memory, `Scripts/measure-long-session.py`: 14.2 to 14.3 MiB before; 14.5 with two watchers; 14.4 with one,
  threads equal to before. The remaining 0.1 MiB is the new feature: five files watched, and the watcher's code.
- Behaviour, in pyte with a throwaway configuration: an atomic save, a broken file and a write in place each reported
  within 0.25 to 0.4 s while idle; a project file created under a missing `.ask` noticed (the "run `ask trust`"
  notice); a replaced executable announced once, after 0.26 s, and not again for a second build.

## Consequences

- Not verified: the reload deferred to a turn's end (no probe drives a turn; the logic is a flag set during the turn and
  read at its end).
- ADR-0033's mechanism (a kqueue on the executable's directory, its own thread) is replaced by this; its behaviour, one
  announcement and a self-check at `/reload`, is unchanged.
- Still owed in 0127: what replacing versus adding does per section, and the setting that makes a layer replace.
