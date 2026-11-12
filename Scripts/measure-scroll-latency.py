#!/usr/bin/env python3
"""Measures how long a wheel step takes to reach the screen (note n18, task t206): the time from a wheel report written to ask's
terminal to the first byte of the frame it causes, through the real binary, a PTY and a local fake provider.

Scripts/measure-scroll-latency.py .build/release/ask [--load] [--busy] [--steps N]

The conversation is long (one reply of a few thousand lines), so there is far to scroll. `--load` keeps every core busy with a loop of
its own, as a build beside ask does; `--busy` keeps ask's own turn busy, a command flooding its block with output, while it scrolls.
Prints the median, the 95th percentile and the worst, in milliseconds. A measurement, not a check: it passes or fails nothing.
"""
import argparse
import fcntl
import importlib.util
import json
import os
import pty
import select
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent", os.path.join(HERE, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
saved = sys.argv
sys.argv = [saved[0]]
spec.loader.exec_module(agent)
sys.argv = saved
ROWS, COLUMNS = 50, 160
MARK = os.urandom(4).hex()  # markers of this run alone: a resumed session may hold any earlier run's


class Pty:
    """ask in a PTY whose output is read on a thread of its own, each read stamped with the time it came."""

    def __init__(self, binary, project, environment, arguments=()):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))
            os.chdir(project)
            os.execve(binary, [binary, *arguments], environment)
        self.reads, self.text, self.lock = [], b"", threading.Lock()
        threading.Thread(target=self.pump, daemon=True).start()

    def pump(self):
        while True:
            try:
                ready, _, _ = select.select([self.fd], [], [], 0.5)
                if not ready:
                    continue
                data = os.read(self.fd, 1 << 16)
            except OSError:
                return
            if not data:
                return
            with self.lock:
                self.reads.append((time.monotonic(), len(data)))
                self.text = (self.text + data)[-(1 << 20):]

    def send(self, data):
        os.write(self.fd, data)

    def until(self, needle, seconds=60):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            with self.lock:
                if needle.encode() in self.text:
                    return True
            time.sleep(0.05)
        import re
        with self.lock:
            tail = re.sub(rb"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\\\)|\x1b[=>()][0-9A-B]?", b"", self.text[-20000:])
        print(re.sub(r" {3,}", "  ", tail.decode(errors="replace"))[-1500:], file=sys.stderr)
        raise AssertionError(f"timed out waiting for {needle!r}")

    def first_read_after(self, instant, seconds=2.0):
        deadline = instant + seconds
        while time.monotonic() < deadline:
            with self.lock:
                later = [at for at, _ in self.reads if at >= instant]
            if later:
                return later[0]
            time.sleep(0.0005)
        return None

    def close(self):
        try:
            os.kill(self.pid, 9)
            os.waitpid(self.pid, 0)
        except OSError:
            pass


def burn():
    while True:
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--load", type=float, nargs="?", const=1.0, default=0.0,
                        help="busy loops per core (1 by default when given); 4 is a machine under heavy contention")
    parser.add_argument("--io", action="store_true", help="also keep the disk busy, writing and syncing a file in a loop")
    parser.add_argument("--busy", choices=["echo", "yes"], help="the turn's command: a shell loop of echo, or yes through head")
    parser.add_argument("--steps", type=int, default=300)
    parser.add_argument("--bursts", type=int, default=0, help="also send this many bursts of 40 wheel steps 5 ms apart, as a trackpad")
    parser.add_argument("--session", help="a session file to resume (a copy is read), in place of the long reply")
    options = parser.parse_args()
    reply = "\n".join(f"- line {n} of a long answer, with **bold** and `code` in it, wrapping a little further" for n in range(4000))
    turn = agent.turn
    script = [turn([("text", reply + "\n\nLONG DONE")], "end_turn")]
    if options.busy:
        flood = {
            "echo": "i=0; while [ $i -lt 600000 ]; do echo \"compiling module $i of a busy build\"; i=$((i+1)); done",
            "yes": "for i in $(seq 1 90); do yes \"compiling module $i of a busy build\" | head -n 20000; sleep 0.1; done",
        }[options.busy]
        script += [turn([("tool", "b1", flood)], "tool_use"), turn([("text", f"BUSY {MARK} DONE")], "end_turn")]
    server = agent.Server(script)
    root = tempfile.mkdtemp()
    project = tempfile.mkdtemp(prefix="measure-scroll-", dir=os.path.join(HERE, "..", ".build"))
    config = root + "/config"
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    environment = agent.environment(root + "/state", server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="kitty")
    burners = []
    arguments = []
    if options.session:
        copy = os.path.join(root, os.path.basename(options.session))
        shutil.copyfile(options.session, copy)
        arguments = ["--resume", copy]
        server.responses = server.responses[1:]
    session = Pty(os.path.abspath(options.binary), project, environment, arguments)
    try:
        session.until("ask>", seconds=180)
        opened = time.monotonic()
        if not options.session:
            session.send(b"write a long answer\r")
            session.until("LONG DONE")
        if options.busy:
            session.send(b"build it\r")
            deadline = time.monotonic() + 60
            while not server.requests and time.monotonic() < deadline:
                time.sleep(0.05)
            time.sleep(1)  # the command started
        if options.load:
            count = max(1, round((os.cpu_count() or 8) * options.load))
            burners = [subprocess.Popen([sys.executable, "-c", "while True: pass"]) for _ in range(count)]
        if options.io:
            writer = f"import os\nwhile True:\n f = open({os.path.join(root, 'io')!r}, 'wb')\n f.write(os.urandom(8 << 20))\n f.flush(); os.fsync(f.fileno()); f.close()"
            burners += [subprocess.Popen([sys.executable, "-c", writer]) for _ in range(2)]
        if options.load or options.io:
            time.sleep(1)
        latencies, lost = [], 0
        for step in range(options.steps):
            # Up, then down, so the window stays inside the history and every step moves it.
            button = 64 if (step // 20) % 2 == 0 else 65
            time.sleep(0.03)
            sent = time.monotonic()
            session.send(f"\x1b[<{button};40;10M".encode())
            first = session.first_read_after(sent)
            if first is None:
                lost += 1
            else:
                latencies.append((first - sent) * 1000)
        settles = []
        for burst in range(options.bursts):
            button = 64 if burst % 2 == 0 else 65
            time.sleep(0.3)
            for _ in range(40):
                session.send(f"\x1b[<{button};40;10M".encode())
                time.sleep(0.005)
            last = time.monotonic()
            # How long the screen goes on after the hand stops: the last byte within a fixed window. Stopping at the first quiet
            # moment missed a frame that came after one (a backlog under contention draws, pauses and draws again).
            time.sleep(1.5)
            with session.lock:
                within = [at for at, _ in session.reads if last <= at <= last + 1.5]
            settles.append(((within[-1] if within else last) - last) * 1000)
        if settles:
            settles.sort()
            print(f"bursts: {len(settles)}, after the last step the screen settled in: median {statistics.median(settles):.1f} ms, "
                  f"worst {settles[-1]:.1f} ms")
        latencies.sort()
        p95 = latencies[int(len(latencies) * 0.95) - 1] if latencies else float("nan")
        p99 = latencies[int(len(latencies) * 0.99) - 1] if latencies else float("nan")
        label = (f"load x{options.load:g} " if options.load else "") + ("io " if options.io else "") + (f"busy:{options.busy} " if options.busy else "") or "idle "
        with session.lock:
            still = f"BUSY {MARK} DONE".encode() not in session.text
        label += "(the turn still busy at the end) " if options.busy and still else "(the turn had ended) " if options.busy else ""
        print(f"{label.strip()}: {len(latencies)} steps, median {statistics.median(latencies):.1f} ms, p95 {p95:.1f} ms, p99 {p99:.1f} ms, "
              f"worst {latencies[-1]:.1f} ms; {lost} with no frame within 2 s")
    finally:
        for burner in burners:
            burner.kill()
        session.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)


if __name__ == "__main__":
    main()
