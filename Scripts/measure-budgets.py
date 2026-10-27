#!/usr/bin/env python3
"""Measure `ask`'s four performance budgets against the real binary.

The budgets are cold start, idle memory, input delay and action-to-action delay.
None of them is reported by the program itself: a program that reports its own
latency reports the flattering number, so every figure here is taken from outside,
over a PTY, by another process.

Method, and why:
  cold start      before fork -> the complete frame showing the prompt in the PTY master.
                  Includes process creation and exec, not just work after the parent resumes.
  idle memory     RSS of the child once it is up and idle. Sampled after the
                  prompt appears, not before.
  input delay     write one byte, then wait for the end of the frame that shows it
                  (the synchronised-output close, ESC[?2026l, after the byte appears).
                  Includes read, decode, layout, diff and write. Frame-based, because a
                  diff renderer sends only what changed, never a repeated prompt.
  action delay    a model's tool call fully received -> the end of the frame that shows
                  the tool finished, for `read` of a small file: ask's own work between the
                  model asking and the user seeing (ADR-0053). Measured by
                  Scripts/measure-action.py against a fake model server on the same clock,
                  with isolated configuration: no request is sent with the user's
                  credentials, and none leaves the machine.

Every figure is the median of N runs, with the spread reported, never the best run.
Percentiles matter because users feel the tail; an average hides it.
"""
import importlib.util, json, math, os, pty, select, statistics, subprocess, sys, tempfile, time

BINARY = sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 15

# The first input rule marks startup without depending on ui.prompt (roadmap 0074).
# Require the closing frame too, not just the separator bytes.
PROMPT = "────".encode()
ISOLATED_CONFIG = tempfile.mkdtemp(prefix="ask-budget-config-")
ISOLATED_STATE = tempfile.mkdtemp(prefix="ask-budget-state-")
FRAME_END = b"\x1b[?2026l"


def spawn():
    pid, fd = pty.fork()
    if pid == 0:
        # ask reads its size immediately: setting it in the parent races exec and the first frame.
        import fcntl, struct, termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        os.environ["TERM"] = "xterm-kitty"
        os.environ["TERM_PROGRAM"] = "kitty"
        # Never the user's credentials or sessions: Enter starts a run, which must fail as signed out. The
        # directories are made in the parent: work in the child before exec would be timed as ask's cold start.
        os.environ["XDG_CONFIG_HOME"] = ISOLATED_CONFIG
        os.environ["XDG_STATE_HOME"] = ISOLATED_STATE
        for key in list(os.environ):
            if key.startswith(("ASK_", "ANTHROPIC_", "OPENAI_", "CODEX_")):
                os.environ.pop(key)
        os.execv(BINARY, [BINARY])
        os._exit(127)
    return pid, fd


def read_frame_showing(fd, token, deadline_s):
    """Read until a frame that shows `token` has ended: `token`, then the synchronised-output close."""
    end = time.monotonic() + deadline_s
    buf = b""
    while time.monotonic() < end:
        r, _, _ = select.select([fd], [], [], max(0.005, min(0.25, end - time.monotonic())))
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
        at = buf.find(token)
        if at >= 0 and buf.find(FRAME_END, at) >= 0:
            return time.monotonic(), buf
    return None


def drain(fd, quiet_s=0.05):
    """Discard pending output, so the next measurement starts from a quiet terminal."""
    while select.select([fd], [], [], quiet_s)[0]:
        try:
            if not os.read(fd, 65536):
                return
        except OSError:
            return


def rss_kb(pid):
    try:
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                             capture_output=True, text=True).stdout.strip()
        return int(out) if out else 0
    except Exception:
        return 0


def one_run():
    t0 = time.monotonic()
    pid, fd = spawn()
    try:
        hit = read_frame_showing(fd, PROMPT, 10.0)
        if hit is None:
            return None
        cold_ms = (hit[0] - t0) * 1000.0

        time.sleep(0.25)                       # let it settle before sampling memory
        idle_kb = rss_kb(pid)

        # input delay: one byte, to the end of the frame that shows it
        drain(fd)
        t1 = time.monotonic()
        os.write(fd, b"x")
        got = read_frame_showing(fd, b"x", 5.0)
        if got is None:
            return None
        input_ms = (got[0] - t1) * 1000.0

        return cold_ms, idle_kb, input_ms
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


def action_probe():
    """Scripts/measure-action.py, loaded as a module and pointed at the same binary."""
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("measure_action", os.path.join(here, "measure-action.py"))
    module = importlib.util.module_from_spec(spec)
    saved, sys.argv = sys.argv, [sys.argv[0], BINARY]
    spec.loader.exec_module(module)
    sys.argv = saved
    return module


def load_budgets():
    """Read the budgets from the binary itself, so there is exactly one definition of them."""
    try:
        out = subprocess.run([BINARY, "--budgets"], capture_output=True, text=True, timeout=30).stdout
        return json.loads(out)
    except Exception as e:
        print("  (could not read budgets from the binary: %s)" % e, file=sys.stderr)
        return None


def main():
    runs, incomplete = [], []
    action = action_probe()
    for i in range(RUNS):
        r = one_run()
        # The action runs in its own process, against a fake model server (ADR-0053).
        shown = action.one_run("read") if r else None
        if r and shown:
            runs.append(r + (shown[0],))
        else:
            incomplete.append(i + 1)
            print("  run %d incomplete (%s)" % (i + 1, "action" if r else "startup/input"), file=sys.stderr)
    if not runs:
        print("no successful runs — the binary never reached its prompt", file=sys.stderr)
        return 1

    def col(idx, scale=1.0, unit=""):
        vals = sorted(r[idx] * scale for r in runs)
        med = statistics.median(vals)
        print("    %-22s median %8.2f %-4s  p95 %8.2f  min %8.2f  max %8.2f"
              % (NAMES[idx], med, unit, vals[math.ceil(len(vals) * 0.95) - 1], vals[0], vals[-1]))

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
    if incomplete:
        print("  INCOMPLETE: %d of %d runs; no green budget result (%s)." %
              (len(incomplete), RUNS, ", ".join(map(str, incomplete))))
    if failed:
        print("  OVER BUDGET: %s" % ", ".join(failed))
        return 1
    if incomplete:
        return 1
    print("  All four within budget.")
    print("  The action is a tool call to its result on screen, for an in-process tool; see")
    print("  Scripts/measure-action.py for the next request and a sandboxed bash command.")
    return 0


if __name__ == "__main__":
    sys.exit(main())