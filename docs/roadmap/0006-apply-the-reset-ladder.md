---
status: in-progress
blocked-by: ["TerminalKit SignalHandler cannot fire from a blocking read"]
date: 2026-10-18
---

# 0006 — Apply the reset ladder on teardown and on signal

**The teardown half is done. The signal half is blocked on TerminalKit, and the blocker is worse than
"not implemented" — wiring the obvious fix makes the process unstoppable. Details below.**

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

## Blocked — the signal cannot be delivered to a blocking read

Probed on a PTY, sending a real `SIGTERM` to a running `ask`:

| Configuration | Result on `SIGTERM` |
|---|---|
| no signal handler (current) | killed by `SIGTERM` — dies, terminal **not** restored |
| TerminalKit's `SignalHandler` wired | **ignores `SIGTERM`** — still running after 4 s |

**TerminalKit's `SignalHandler` cannot fire here, and installing it is worse than the bug.**
`DispatchSource.makeSignalSource(signal:queue:)` is given `.main`, and `ask`'s main thread is blocked
inside `read(into:)` waiting for input. The main queue never runs, the `AsyncStream` never yields, and
the process simply stops responding to `SIGTERM`.

That is the second time this session a correct-looking primitive turned out not to do its job, and it
is the same shape as the earlier harness defect: something that returns and does nothing is worse than
nothing, because it looks handled.

**Why it is not worked around here.** A signal installer is generic, so the white paper puts it in the
shared package rather than in `ask` — and the one in TerminalKit is the wrong shape. Fixing it is a
change to a package Atelier and KittyCode also link, so it is TerminalKit's change to make and record.
The white paper's rule against duplicating a shared primitive applies with more force here, not less.

**What the fix needs to be.** Deliver the signal off the main thread, so a blocked read cannot starve
it. A `sigaction` handler writing to a self-pipe, drained by a `Task`, would do it without
`DispatchQueue` — which this project bans — and without the main-queue starvation.

`SignalShutdown` stays in `ask` as the tested model of *what* must happen when the signal lands. It is
not wired, and the wiring is blocked.

## Still owed

- The `128 + signo` exit convention depends on knowing which signal fired. TerminalKit's
  `onShutdown` does not report it, so a `SIGINT` would exit `143` rather than `130`. That is a second
  change the same fix should carry.
- `SIGHUP` means the terminal closed, so there is nothing left to restore — restoring is pointless
  there, and the unit tests cover the sequence rather than claiming it matters in that case.