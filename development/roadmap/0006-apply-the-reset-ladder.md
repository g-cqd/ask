---
status: done
blocked-by:
date: 2026-10-18
---

# 0006 — Apply the reset ladder on teardown and on signal

**Done.** Every exit path in the loop writes tier 1, and a shutdown signal both restores the terminal and
dies with the shell-conventional status. The blocker that stood here is resolved in TerminalKit ADR-0013.

## Done — every exit path in the loop

`runAskTUI(on:)` takes its connection, so the loop's exit paths are drivable from a test rather than
asserted. `TerminalTeardown` holds the bytes so all of them write the same thing.

Four tests, red first against the missing API: Ctrl-D, Ctrl-C, a failed read, and `termios` restored on
the normal path. The read-error one earns the entry — the read loop is the only place the function
throws, so a teardown written inline on the normal return is skipped exactly there.

Guard probed by deletion: removing the teardown write turns three of the four red.

## Done — the shutdown sequence itself, tested

`SignalShutdown` restores the terminal and then requests an exit, with the exit injected so the
sequence is testable. Nine tests: the ladder is written before the exit is requested, `termios` is
restored, all four shutdown signals report `128 + signo`, the alternate screen is left, and **the
terminal is restored even when the write fails** — a dead terminal must not leave `termios` raw.

Guard probed both ways: swallowing the signal turns four tests red; skipping the restore turns six.

## Resolved — the signal could not be delivered to a blocking read, and now can

Probed on a PTY, sending a real `SIGTERM` to a running `ask`:

| Configuration | Result on `SIGTERM` |
|---|---|
| no signal handler (current) | killed by `SIGTERM` — dies, terminal **not** restored |
| TerminalKit's `SignalHandler` wired | **ignores `SIGTERM`** — still running after 4 s |

**Found:** `DispatchSource.makeSignalSource(signal:queue:)` was given `.main`, and `ask`'s main thread
is blocked inside `read(into:)`. The main queue never ran, so the process stopped responding to
`SIGTERM` — and installing that handler was **worse than the bug**, leaving an unstoppable process.

**Fixed in TerminalKit ADR-0013:** a `sigaction` handler writes one byte to a pipe and returns — the only
async-signal-safe thing worth doing — and a dedicated `Thread` drains it. Neither the main thread nor a
cooperative pool thread is involved. `onShutdown` now reports which signal fired, which is what
`128 + signo` requires.

Verified end to end against the real binary on a PTY, for both shutdown signals:

    SIGTERM: exit=143  raw-restored=True  alt-screen-left=True  cursor=True
    SIGINT : exit=130  raw-restored=True  alt-screen-left=True  cursor=True

Exit 130 for SIGINT is the part the old signature could not produce at all.

## Notes

- `SIGHUP` is not handled. That is correct rather than an omission — `SIGHUP` means the terminal
  closed, so there is nothing left to restore — and it is stated here so it is not mistaken for a gap.
- `SignalShutdown` stays in `ask` as the tested model of *what* happens; the delivery mechanism is
  TerminalKit's, per the rule that generic tools live in the shared package.