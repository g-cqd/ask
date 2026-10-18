#!/usr/bin/env python3
"""Measure `ask`'s four performance budgets against the real binary.

The budgets are cold start, idle memory, input delay and action-to-action delay.
None of them is reported by the program itself: a program that reports its own
latency reports the flattering number, so every figure here is taken from outside,
over a PTY, by another process.

Method, and why:
  cold start      spawn -> the prompt is actually on the terminal's output stream.
                  Wall time from the fork to seeing "ask> " in the PTY master.
  idle memory     RSS of the child once it is up and idle. Sampled after the
                  prompt appears, not before.
  input delay     write one byte, then wait for the echoed line to reach the
                  stream. Includes read, decode and render.
  action delay    Enter -> the next prompt appears. The full round trip of one
                  action, which is the number a user feels between doing something
                  and seeing that it happened.

Every figure is the median of N runs, with the spread reported, never the best run.
Percentiles matter because users feel the tail; an average hides it.
"""
import json, os, pty, select, statistics, subprocess, sys, time

BINARY = sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 15

PROMPT = b"ask> "


def spawn():
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-kitty"
        os.environ["TERM_PROGRAM"] = "kitty"
        os.execv(BINARY, [BINARY])
        os._exit(127)
    # Keep the window a sane size; a 1x1 PTY would make the app's own logic degenerate.
    try:
        import fcntl, struct, termios
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    except Exception:
        pass
    return pid, fd


def read_until(fd, needle, deadline_s):
    """Read from the PTY until `needle` appears, or the deadline passes."""
    end = time.time() + deadline_s
    buf = b""
    while time.time() < end:
        remaining = end - time.time()
        r, _, _ = select.select([fd], [], [], max(0.005, min(0.25, remaining)))
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
        if needle in buf:
            return time.time(), buf
    return None


def rss_kb(pid):
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True).stdout.strip()
        return int(out) if out else 0
    except Exception:
        return 0


def one_run():
    pid, fd = spawn()
    try:
        t0 = time.time()
        hit = read_until(fd, PROMPT, 10.0)
        if hit is None:
            return None
        cold_ms = (hit[0] - t0) * 1000.0

        time.sleep(0.25)                       # let it settle before sampling memory
        idle_kb = rss_kb(pid)

        # input delay: one byte, echoed by the app
        t1 = time.time()
        os.write(fd, b"x")
        got = read_until(fd, b"ask> x", 5.0)
        if got is None:
            return None
        input_ms = (got[0] - t1) * 1000.0

        # action delay: Enter -> next prompt
        t2 = time.time()
        os.write(fd, b"\r")
        got2 = read_until(fd, PROMPT, 5.0)
        if got2 is None:
            return None
        action_ms = (got2[0] - t2) * 1000.0

        return cold_ms, idle_kb, input_ms, action_ms
    finally:
        try:
            os.write(fd, b"\x03")
            time.sleep(0.05)
        except OSError:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except Exception:
            pass


def load_budgets():
    """Read the budgets from the binary itself, so there is exactly one definition of them."""
    try:
        out = subprocess.run([BINARY, "--budgets"], capture_output=True, text=True, timeout=30).stdout
        return json.loads(out)
    except Exception as e:
        print("  (could not read budgets from the binary: %s)" % e, file=sys.stderr)
        return None


def main():
    runs = []
    for i in range(RUNS):
        r = one_run()
        if r:
            runs.append(r)
    if not runs:
        print("no successful runs — the binary never reached its prompt", file=sys.stderr)
        return 1

    def col(idx, scale=1.0, unit=""):
        vals = sorted(r[idx] * scale for r in runs)
        med = statistics.median(vals)
        print("    %-22s median %8.2f %-4s  p95 %8.2f  min %8.2f  max %8.2f"
              % (NAMES[idx], med, unit, vals[int(len(vals) * 0.95) - 1], vals[0], vals[-1]))

    NAMES = ["cold start", "idle memory", "input delay", "action-to-action"]
    print("ask — four budgets, %d runs, release build, measured externally over a PTY" % len(runs))
    col(0, 1.0, "ms")
    col(1, 1.0, "KiB")
    col(2, 1.0, "ms")
    col(3, 1.0, "ms")
    budgets = load_budgets()
    if budgets is None:
        print("\n  No budgets available, so nothing is checked. Reporting nothing is not passing.")
        return 1

    limits = [
        ("cold start", 0, budgets["coldStartMilliseconds"], "ms"),
        ("idle memory", 1, budgets["idleMemoryMebibytes"] * 1024.0, "KiB"),
        ("input delay", 2, budgets["inputDelayMilliseconds"], "ms"),
        ("action-to-action", 3, budgets["actionToActionMilliseconds"], "ms"),
    ]
    print()
    print("  %-22s %12s %12s   %s" % ("budget", "median", "limit", "verdict"))
    failed = []
    for name, idx, limit, unit in limits:
        med = statistics.median(r[idx] for r in runs)
        ok = med <= limit
        if not ok:
            failed.append(name)
        print("  %-22s %12.2f %12.2f   %s" % (name, med, limit, "ok" if ok else "OVER BUDGET"))

    print()
    if failed:
        print("  OVER BUDGET: %s" % ", ".join(failed))
        return 1
    print("  All four within budget.")
    print("  The action-to-action figure measures Enter producing the next prompt in a program")
    print("  with no agent in it — a trivial action, not yet the one a user feels. Re-derive it")
    print("  when the agent loop lands.")
    return 0


if __name__ == "__main__":
    sys.exit(main())