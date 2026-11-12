#!/usr/bin/env python3
"""Probe a tool's picture on the screen (roadmap 0208) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-images.py .build/release/ask

The model reads a PNG with the read tool. Its block shows the picture's row under the header (`PNG · 3×2 · … B`), and so does
the session resumed with --continue. As Ghostty, whose answer to kitty's graphics query the probe gives as kitty would, the
picture is sent and placed virtually, and its placeholder cells are drawn; a click folds the block to one line, another opens it;
a JPEG is sent made a PNG.
As Terminal.app, nothing is asked or sent. Hermetic: a picture made here, no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import fcntl
import re
import shutil
import struct
import subprocess
import sys
import termios
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def png(width, height):
    """A real PNG of `width` by `height` red pixels."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + b"\xff\x00\x00" * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def with_pixels(terminal, columns=100, rows=40):
    """The PTY's size with pixels too (10x20 cells), as a terminal that draws images reports it."""
    fcntl.ioctl(terminal.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, columns * 10, rows * 20))


def answer_graphics_query(terminal):
    """Answers kitty's graphics query once it was sent, as kitty does: OK for the id asked about."""
    terminal.until(lambda: b"\x1b_G" in bytes(terminal.raw) and b"a=q" in bytes(terminal.raw))
    asked = re.search(rb"\x1b_G[^\x1b]*i=(\d+)[^\x1b]*a=q|\x1b_G[^\x1b]*a=q[^\x1b]*i=(\d+)", bytes(terminal.raw))
    query_id = (asked.group(1) or asked.group(2)).decode()
    terminal.send(f"\x1b_Gi={query_id};OK\x1b\\".encode())


def as_terminal_app(project, environment, state):
    """The same session as Terminal.app: no query, nothing sent, the picture's line only."""
    environment = dict(environment, TERM_PROGRAM="Apple_Terminal", TERM="xterm-256color")
    terminal = probe.Terminal(project, environment, rows=40, resume=True)
    try:
        terminal.until(lambda: "SEEN IT" in terminal.text())
        probe.time.sleep(0.5)
        terminal.pump()
        check("as Terminal.app, nothing is asked or sent", b"\x1b_G" not in bytes(terminal.raw))
    finally:
        terminal.close()


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-images-")
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    picture = png(3, 2)
    with open(os.path.join(project, "shot.png"), "wb") as file:
        file.write(picture)
    # A JPEG of it, made by macOS's own sips: drawn too, made a PNG first (kitty takes PNG or raw pixels).
    subprocess.run(["sips", "-s", "format", "jpeg", os.path.join(project, "shot.png"), "--out",
                    os.path.join(project, "photo.jpg")], check=True, capture_output=True)
    turn = probe.agent.turn
    server = probe.agent.Server([turn([("call", "r1", "read", {"path": "shot.png"})], "tool_use"),
                                 turn([("text", "SEEN IT")], "end_turn"),
                                 turn([("call", "r2", "read", {"path": "photo.jpg"})], "tool_use"),
                                 turn([("text", "SEEN TOO")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    row = f"PNG · 3×2 · {len(picture)} B"
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        with_pixels(terminal)  # once ask runs: the child sets the size as it starts, and would undo this
        answer_graphics_query(terminal)
        check("as Ghostty, ask asks whether kitty graphics are drawn", True)
        terminal.send(b"look at the shot\r")
        terminal.until(lambda: "SEEN IT" in terminal.text())
        check(f"the read tool's picture shows as a row in its block: {row}", row in terminal.text())
        deadline = probe.time.monotonic() + 3
        while b"U=1" not in bytes(terminal.raw) and probe.time.monotonic() < deadline:
            terminal.pump()
        raw = bytes(terminal.raw)
        check("the answer was not typed into the input", "Gi=" not in terminal.text())
        check("the picture is sent as PNG and placed virtually", b"a=t" in raw and b"f=100" in raw and b"U=1" in raw)
        check("its placeholder cells are drawn", "\U0010EEEE".encode() in raw)
        # A click on the block folds it to one line, its header, which says what the picture is; a click there opens it
        # (the owner, 2026-11-12).
        cells = lambda: sum("\U0010EEEE" in line for line in terminal.screen.display)
        terminal.until(lambda: cells() > 0)
        terminal.click(row)
        terminal.until(lambda: cells() == 0)
        terminal.repaint()  # pyte has no regional scrolling: what moved is drawn again before it is read
        header = [line for line in terminal.screen.display if "read" in line and "PNG · 3×2" in line]
        check("a click folds the block to one line, its header saying what the picture is",
              len(header) == 1 and not any(line.strip().startswith("PNG ·") for line in terminal.screen.display))
        terminal.click("PNG · 3×2")
        terminal.until(lambda: cells() > 0)
        terminal.repaint()
        check("a click on that line opens it, the picture then its details", row in terminal.text())
        terminal.send(b"look at the photo\r")
        terminal.until(lambda: "SEEN TOO" in terminal.text())
        check("a JPEG shows its row too", "JPEG · 3×2" in terminal.text())
        # Its transmission is a PNG's: base64 of the PNG signature, a second time, and never a JPEG's (/9j/).
        terminal.until(lambda: bytes(terminal.raw).count(b"iVBORw0KGgo") >= 2)
        check("and is sent to the terminal made a PNG", b"/9j/" not in bytes(terminal.raw))
        terminal.send(b"/quit\r")
        terminal.close()
        terminal = probe.Terminal(project, environment, rows=40, resume=True)
        terminal.until(lambda: "SEEN IT" in terminal.text())
        check("and again in the session resumed", row in terminal.text())
        terminal.close()
        terminal = None
        as_terminal_app(project, environment, state)
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
