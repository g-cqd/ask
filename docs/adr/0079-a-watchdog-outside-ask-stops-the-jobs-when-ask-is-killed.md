---
status: accepted
date: 2026-10-24
---

# 0079 — A watchdog outside ask stops the jobs when ask is killed

## Context

Every command ask runs is a job in a session of its own (ADR-0029), so a Ctrl-C on the terminal cannot reach it, and ask stops them all
on each exit it can see: the end of `-p`, closing the screen, SIGTERM and SIGINT. ADR-0029 and roadmap 0031 recorded the gap: a
SIGKILL of ask, or a crash, cannot be seen, and the jobs, a dev server, a watcher, a runaway build, would outlive ask for good.
"Killing ask leaves no job running" was only partly true. ADR-0029 named two fixes, a watchdog holding a pipe and a kqueue
`NOTE_EXIT` watcher; either has to be a process other than ask, because nothing inside a killed process can act.

## Decision

1. **One small shell, outside ask, watches a pipe ask holds.** `/bin/sh` is started in a session of its own with the read end of a
   pipe as its standard input and nothing else inherited. ask writes `+GROUP` when a job starts and `-GROUP` when it ends, one short
   line each (a short write to a pipe is atomic). When the pipe closes, which the kernel does when ask dies by any means, the shell
   stops each group still listed as ask stops a job: SIGTERM to the group, two seconds, SIGKILL to the group.
   This is the pipe form, not the kqueue form, because end of file needs no pid, cannot be reused, and is reported for a crash and a
   SIGKILL alike.
2. **A group is listed only while its job runs.** A job leads its own session, so its group is its process id. It is listed when the
   process starts and taken off when the job ends, because a group id can be used again and the shell must never stop something that
   is not ours. A background child that outlives its job's shell is not covered, as it was not before.
3. **Nothing happens until the first job, and nothing waits.** The pipe is made when the first job is listed (microseconds), and the
   shell is started on a thread of its own: what ask writes meanwhile waits in the pipe. A job's start does not pay for a process.
4. **Ask cannot be hurt by it.** The write end does not raise SIGPIPE if the shell is gone, and does not block if the shell stops
   reading: either way ask goes on, and ``JobWatchdog/protection`` says `unavailable`. The end is not inherited by any job
   (swift-subprocess starts children with `POSIX_SPAWN_CLOEXEC_DEFAULT`, and the descriptor is `FD_CLOEXEC` besides), because a job
   holding it would keep the pipe open after ask died.
5. **It is best effort and says what it is.** If `/bin/sh` cannot start ask runs as it did before. The shell itself can be killed, and
   a SIGKILL that lands in the milliseconds before it has started is not covered.
6. **Normal exits are unchanged.** The watchdog is a second net: ask still stops its jobs itself, and when the table is let go the
   pipe closes and the shell ends with nothing to stop.

## Consequences

One extra process, a `/bin/sh` sleeping in `read`, for the life of ask once a job has started. It is ask's child, reaped by a thread that
waits for it, so it never lingers as a zombie, and it ends when the pipe closes.

Measured on shipping builds, 60 interleaved `ask -p` runs of one `bash` call against the previous binary on a loaded host: peak memory
20.77 MiB against 20.67 (+0.10), CPU 60.1 ms against 57.6 (+2.5, the shell's own start-up, in another process), wall time no worse
(median 84.7 ms against 101.7, first quartile 58.5 against 61.9). The first registration in a process costs a median 63 µs (p95 384 µs),
later ones 1 µs. A session that never starts a job pays nothing: no pipe, no thread, no process.

## Probes

Unit tests with real processes (the pipe closed as the kernel closes it), mutants on the registration, the shell's script and the
spawn, and a real-binary probe that starts a job with `ask -p`, holds the model's next answer, sends SIGKILL to ask and looks at the
job (`Scripts/probe-job-watchdog.py`, with a control that shows the job surviving without the watchdog).

## Addendum (2026-10-24, from the second analysis pass)

A TLA+ model of the watchdog (`ask-formal-report/tla/JobWatchdog.tla`) shows the one way it can signal a process that is not an ask job:
the job's leader exits, another process takes its pid and leads a group, and ask is killed by SIGKILL before `Job.finish` has released the
old pid; the shell then stops the new group. Without pid reuse the model holds. The window is the time between a leader's exit and the
release (microseconds, and POSIX keeps a pid reserved while its group still has members), and it needs ask killed inside it and the pid
reused inside it. It is not tested, because pid allocation cannot be steered. If it ever matters, the shell can compare the leader's
start time recorded at registration with the one `ps` reports before it signals. Not done: the cost is a second field on every line of
the protocol and a `ps` per group, for a case that needs three independent rarities to line up.
