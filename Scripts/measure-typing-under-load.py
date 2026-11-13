#!/usr/bin/env python3
"""Measures how long a typed character takes to show while ask and the machine are busy (roadmap 0230, notes n18 and n55): the time
from a key written to ask's terminal to the read that carries that character back, through the real binary, a PTY and a local fake
provider.

Scripts/measure-typing-under-load.py .build/release/ask [--load [N]] [--busy echo|yes] [--keys N] [--session FILE] [--wheel N]

Each key is a character of its own (U+2460 on), so the read that shows it is told from the turn's output and from a redraw of what
was typed before; the draft is erased every 40 keys and never sent. `--busy` keeps ask's own turn busy (a command flooding its block);
`--load` keeps every core busy as a build beside ask does; `--session` resumes a copy of a long session; `--wheel N` writes N wheel
reports just before each key, a trackpad's fling, so the key waits behind them (note n55).

The floor is measured first: the same keys through `/bin/cat` in a PTY, echoed by the terminal driver, under the same load. It is
what the measuring itself costs; a number below it says nothing about ask. The harness takes the role of the app in focus and the
highest quality of service for itself, as ask does, so its reader is not held behind the load.
Prints the median, the 95th percentile and the worst, in milliseconds. A measurement, not a check: it passes or fails nothing.
"""
import argparse
import ctypes
import importlib.util
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("scroll", os.path.join(HERE, "measure-scroll-latency.py"))
scroll = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scroll)
agent = scroll.agent


def raise_priority():
    """The role of the app in focus for this process and the highest quality of service for the calling thread; True when taken."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        role = libc.setpriority(6, 0, 1) == 0  # PRIO_DARWIN_ROLE, PRIO_DARWIN_ROLE_UI_FOCAL
        qos = libc.pthread_set_qos_class_self_np(0x21, 0) == 0  # QOS_CLASS_USER_INTERACTIVE
        return role and qos
    except (OSError, AttributeError):
        return False


class Typist(scroll.Pty):
    """A PTY whose reads are kept whole, each with the time it came, so the read that carries a given character is found."""

    def __init__(self, *arguments):
        self.chunks = []
        super().__init__(*arguments)

    def pump(self):
        raise_priority()
        import select
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
            now = time.monotonic()
            with self.lock:
                self.chunks.append((now, data))
                self.text = (self.text + data)[-(1 << 20):]

    def shown(self, needle, sent, seconds=3.0):
        """When the first read at or after `sent` that carries `needle` came, or None within `seconds`."""
        deadline = sent + seconds
        start = 0
        while time.monotonic() < deadline:
            with self.lock:
                chunks = self.chunks[start:]
                start = max(0, len(self.chunks) - 1)
            previous = b""
            for at, data in chunks:
                if at >= sent and needle in previous[-3:] + data:
                    return at
                previous = data
            time.sleep(0.0003)
        return None


def type_keys(terminal, count, first, wheel=0):
    """Types `count` characters, each new to the terminal, 30 ms apart, each after `wheel` wheel reports; the delays in milliseconds,
    and how many never showed."""
    delays, lost = [], 0
    for index in range(count):
        if index and index % 40 == 0:
            terminal.send(b"\x15")
            time.sleep(0.2)
        key = chr(first + index % 150).encode()
        time.sleep(0.03)
        if wheel:
            # Up, then down, so the window stays inside the history and every report moves it.
            button = 64 if index % 2 == 0 else 65
            terminal.send(f"\x1b[<{button};40;10M".encode() * wheel)
        sent = time.monotonic()
        terminal.send(key)
        at = terminal.shown(key, sent)
        if at is None:
            lost += 1
        else:
            delays.append((at - sent) * 1000)
    terminal.send(b"\x15")
    return delays, lost


def line(label, delays, lost):
    delays = sorted(delays)
    if not delays:
        return f"{label}: nothing showed ({lost} lost)"
    p95 = delays[max(0, int(len(delays) * 0.95) - 1)]
    return (f"{label}: {len(delays)} keys, median {statistics.median(delays):.1f} ms, p95 {p95:.1f} ms, worst {delays[-1]:.1f} ms; "
            f"{lost} not shown within 3 s")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary")
    parser.add_argument("--load", type=float, nargs="?", const=1.0, default=0.0, help="busy loops per core (1 when given alone)")
    parser.add_argument("--busy", choices=["echo", "yes"], help="keep ask's turn busy with a command flooding its block")
    parser.add_argument("--keys", type=int, default=120)
    parser.add_argument("--session", help="a session file to resume (a copy is read)")
    parser.add_argument("--wheel", type=int, default=0, help="wheel reports written just before each key")
    options = parser.parse_args()
    raised = raise_priority()
    flood = {
        "echo": "i=0; while [ $i -lt 600000 ]; do echo \"compiling module $i of a busy build\"; i=$((i+1)); done",
        "yes": "for i in $(seq 1 90); do yes \"compiling module $i of a busy build\" | head -n 20000; sleep 0.1; done",
    }
    script = [agent.turn([("text", "ready")], "end_turn")]
    if options.busy:
        script = [agent.turn([("tool", "b1", flood[options.busy])], "tool_use"), agent.turn([("text", "BUSY DONE")], "end_turn")]
    server = agent.Server(script)
    root = tempfile.mkdtemp()
    project = tempfile.mkdtemp(prefix="measure-typing-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(root + "/config/ask")
    with open(root + "/config/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    environment = agent.environment(root + "/state", server.url, config=root + "/config")
    environment.update(TERM="xterm-256color", TERM_PROGRAM="kitty")
    arguments = []
    if options.session:
        copy = os.path.join(root, os.path.basename(options.session))
        shutil.copyfile(options.session, copy)
        arguments = ["--resume", copy]
    burners = []
    if options.load:
        count = max(1, round((os.cpu_count() or 8) * options.load))
        burners = [subprocess.Popen([sys.executable, "-c", "while True: pass"]) for _ in range(count)]
        time.sleep(1)
    session = None
    try:
        floor = Typist("/bin/cat", "/", {"TERM": "xterm-256color"})
        time.sleep(0.3)
        print(line("floor (the terminal driver's echo)", *type_keys(floor, min(options.keys, 60), 0x2460)))
        floor.close()
        session = Typist(os.path.abspath(options.binary), project, environment, arguments)
        session.until("ask>", seconds=180)
        if options.busy:
            session.send(b"build it\r")
            deadline = time.monotonic() + 60
            while not server.requests and time.monotonic() < deadline:
                time.sleep(0.05)
            session.until("Allow it?", seconds=30)
            session.send(b"y\r")  # the approval, or the keys would go to its choices and the command never run
            time.sleep(1.5)  # the command is flooding
        delays, lost = type_keys(session, options.keys, 0x2460, options.wheel)
        with session.lock:
            ended = b"BUSY DONE" in session.text
        label = (f"load x{options.load:g} " if options.load else "") + (f"busy:{options.busy} " if options.busy else "") or "idle "
        label += "(session resumed) " if options.session else ""
        label += f"behind {options.wheel} wheel reports " if options.wheel else ""
        label += "(the turn had ended) " if options.busy and ended else ""
        print(line(label.strip(), delays, lost))
        print(f"harness raised to the focal role: {raised}; budget for input delay: 4 ms (ask --budgets), measured idle by measure-budgets.py")
    finally:
        for burner in burners:
            burner.kill()
        if session:
            session.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)


if __name__ == "__main__":
    main()
