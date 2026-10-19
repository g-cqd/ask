---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0029
---

# 0031 — Background jobs and waits

Today `bash` holds the turn until its command exits. A build, a server or a watcher either stalls the run
or gets killed at the time limit. A long command's middle is cut away, and that is the part with the error.

## The work

- **`bash` yields.** It takes `yield_seconds`. A command still running at that point becomes a job with an
  identifier, and the tool returns its output so far.
- **Job tools.**
  - `wait` for a job: until it exits, until its output contains some text, or until a file exists or a port
    accepts connections, each with a timeout.
  - `job_input` writes to a job's standard input.
  - `job_stop` ends a job's process group.
- **Full output kept.** Each command's whole output goes to a file under the session's state, and the
  truncated result names that file, so the model can `read` the part that was cut.
- **Waits are events,** not polling: kqueue for process exit and for files, and connection attempts with
  backoff for ports.

## Done when

Probes show:
- a server started by `bash` keeps running across turns, and is waited on until ready;
- `job_stop` ends it and every child it started;
- a 10 MB log's cut middle is recoverable from the named file;
- killing ask leaves no job running.

## Done (2026-10-19)

Everything listed above landed (ADR-0029), with probes F, G and screen E and a live run.

Two parts of "done when" are only partly met:
- **"Killing ask leaves no job running"** holds for every exit ask can see: the end of `-p`, closing the
  screen, SIGTERM and SIGINT. It does not hold for SIGKILL, which ask cannot observe. A watchdog would close
  that gap; ADR-0029 records the options.
- **The cut-middle check** used 10.9 MB of `seq` output rather than a log file.
