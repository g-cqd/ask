#!/usr/bin/env python3
"""What a long conversation costs the screen (roadmap 0088 step 2, TerminalKit 0023): resident size and frame times.

Usage: Scripts/measure-long-session.py .build/release/ask [SESSION.jsonl] [runs]

Without a session, a fresh screen. With one, a copy of it (the original is never opened) is resumed in an isolated state
and configuration, signed out, at 120x40. Measured per run, then the median over runs:

  open:     spawn -> the first frame showing the input's rule, once the output has been quiet for 0.5 s (minus that 0.5 s)
  rss:      resident size once open and quiet, median of five samples (ps)
  input:    one typed byte -> the end of the frame that shows it
  page:     PageUp -> the end of its frame, median and worst of 30 pages up
  rss2:     resident size after the pages, so building and keeping far-off lines shows
  resize:   a new width (120 -> 100 columns) -> the end of the frame drawn at it
"""
import os
import pty
import select
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
SESSION = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
RUNS = int(sys.argv[3]) if len(sys.argv) > 3 else 3
RULE = "────".encode()
FRAME_END = b"\x1b[?2026l"
PAGE_UP = b"\x1b[5~"


def spawn(project, config, state, arguments):
    pid, fd = pty.fork()
    if pid == 0:
        import fcntl, struct, termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        os.chdir(project)
        os.environ.update(TERM="xterm-kitty", TERM_PROGRAM="kitty", XDG_CONFIG_HOME=config, XDG_STATE_HOME=state)
        for key in list(os.environ):
            if key.startswith(("ASK_", "ANTHROPIC_", "OPENAI_", "CODEX_")):
                os.environ.pop(key)
        os.execv(BINARY, [BINARY, *arguments])
        os._exit(127)
    return pid, fd


def read_until(fd, done, deadline_s):
    """Reads until `done(buffer)`; returns the time it became true and the buffer, or None."""
    end, buf = time.monotonic() + deadline_s, b""
    while time.monotonic() < end:
        if not select.select([fd], [], [], 0.01)[0]:
            continue
        try:
            chunk = os.read(fd, 1 << 16)
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
        if done(buf):
            return time.monotonic(), buf
    return None


def quiet(fd, seconds):
    """Reads until nothing arrives for `seconds`; returns when the last byte arrived."""
    last = time.monotonic()
    while select.select([fd], [], [], seconds)[0]:
        try:
            if not os.read(fd, 1 << 16):
                break
        except OSError:
            break
        last = time.monotonic()
    return last


def rss_kib(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) if out else 0


def frame_after(fd, data):
    start = time.monotonic()
    os.write(fd, data)
    got = read_until(fd, lambda b: FRAME_END in b, 5.0)
    return (got[0] - start) * 1000 if got else float("nan")


def resize(fd, columns):
    """A new width: SIGWINCH, then the end of the frame drawn at that width."""
    import fcntl, struct, termios
    start = time.monotonic()
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, columns, 0, 0))
    got = read_until(fd, lambda b: FRAME_END in b, 10.0)
    return (got[0] - start) * 1000 if got else float("nan")


def one_run():
    root = tempfile.mkdtemp(prefix="ask-long-")
    project, config, state = (os.path.join(root, name) for name in ("project", "config", "state"))
    for path in (project, config, state):
        os.makedirs(path)
    arguments = []
    if SESSION:
        copy = os.path.join(root, os.path.basename(SESSION))
        shutil.copyfile(SESSION, copy)
        arguments = ["--resume", copy]
    t0 = time.monotonic()
    pid, fd = spawn(project, config, state, arguments)
    try:
        if read_until(fd, lambda b: RULE in b and FRAME_END in b[b.find(RULE):], 30.0) is None:
            return None
        opened = (quiet(fd, 0.5) - t0) * 1000
        rss = statistics.median(rss_kib(pid) for _ in range(5) if time.sleep(0.1) is None)
        quiet(fd, 0.1)
        typed = frame_after(fd, b"x")
        quiet(fd, 0.1)
        pages = []
        for _ in range(30):
            pages.append(frame_after(fd, PAGE_UP))
            quiet(fd, 0.02)
        time.sleep(0.3)
        rss2 = rss_kib(pid)
        resized = resize(fd, 100)
        return opened, rss / 1024, typed, statistics.median(pages), max(pages), rss2 / 1024, resized
    finally:
        try:
            os.write(fd, b"\x15\x03\x03")
            time.sleep(0.1)
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except OSError:
            pass
        os.close(fd)
        shutil.rmtree(root, ignore_errors=True)


def main():
    rows = [r for r in (one_run() for _ in range(RUNS)) if r]
    if not rows:
        sys.exit("no run completed")
    names = ["open ms", "rss MiB", "input ms", "page ms", "page worst ms", "rss after pages MiB", "resize ms"]
    print(f"{os.path.basename(SESSION) if SESSION else 'fresh'}: {len(rows)} runs")
    for index, name in enumerate(names):
        values = [r[index] for r in rows]
        print(f"  {name:20} median {statistics.median(values):8.1f}   [{', '.join(f'{v:.1f}' for v in values)}]")


main()
