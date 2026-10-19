---
status: accepted
date: 2026-10-19
---

# 0029 — Every command is a job; long ones outlive their turn, never ask

## Context

`bash` held the turn until its command exited. A server, a watcher or a long build either stalled the run or
was killed at the time limit. A long result kept its head and tail and dropped the middle, which is where a
build error usually is. Roadmap 0031.

## Decision

- **One path.** Every `bash` command runs as a `Job` in its own session, registered in a `JobTable`. The table
  is shared by `bash`, `wait`, `job_input` and `job_stop`, and it belongs to the ask process, not to a turn.
- **`bash` without `yield_seconds`** behaves as before: standard input closed, stopped at its timeout, and
  stopped on abort.
- **`bash` with `yield_seconds`** leaves a command that is still running at that point running as a job,
  with standard input open, and returns its output so far.
- **`wait` returns on the first of:**
  - a job ending;
  - a job printing a text, even one split across chunks or begun before the wait started (a 4 KiB window of
    recent output seeds the search);
  - a file existing: kqueue on its deepest existing directory, blocking on a dedicated thread, woken by an
    `EVFILT_USER` event when cancelled;
  - a local port accepting connections.

  A timeout is reported, not raised as an error.
- **Ports are the one wait that retries.** A refused connection raises no event, so `wait` tries again with
  backoff, from 50 ms to 1 s. Each attempt is non-blocking and bounded at 250 ms, because a port that is
  bound but not listening drops IPv4 connections on macOS: probed at 7.9 s to `ETIMEDOUT`.
- **Whole output** streams to an owner-only file under the project's session directory, capped at 64 MiB. It
  is kept only when the result is cut, and the result names it.
- **Stopping is per group:** SIGTERM, two seconds, then SIGKILL. `job_stop` that stops a running job is a
  success.
- **Exit.** ask stops every job when `-p` ends, when the screen closes, and on a shutdown signal. The screen's
  signal path cannot wait, so it sends SIGTERM and then SIGKILL at once.

## The gap

A SIGKILL of ask cannot be observed, and jobs in their own sessions survive it. Two fixes are possible:
- a watchdog process holding a pipe whose end-of-file means ask died;
- a kqueue `NOTE_EXIT` watcher on ask's pid.

Neither is built yet.

## Evidence (diary 2026-10-19-15)

- **Tests:** 17, with real processes and virtual clocks.
- **Bugs the tests found before any probe:** a file-wait race that hung, and a text split across a report
  that was never found.
- **Mutations:** 12 compiling ones caught, two of them by probes: removing the stop on a screen signal, and
  removing the stop when `-p` ends.
- **Probes:**
  - F and G (fake model, real `http.server`): yielded, waited on, fetched, stopped; 10.9 MB of output
    recovered from the named file; a job left running is gone after `-p`.
  - Screen E: SIGTERM gives 143, and the job is gone.
- **Live:** asked plainly to serve, check and stop, the model used `yield_seconds`, `wait` on the port,
  `curl` and `job_stop`. The port was closed after the run.
