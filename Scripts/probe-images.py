#!/usr/bin/env python3
"""Probe a tool's picture on the screen (roadmap 0208) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-images.py .build/release/ask

The model reads a PNG with the read tool. Its block shows the picture's row under the header (`PNG · 3×2 · … B`), and so does the
session resumed with --continue. Hermetic: a picture made here, no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import shutil
import struct
import sys
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
    turn = probe.agent.turn
    server = probe.agent.Server([turn([("call", "r1", "read", {"path": "shot.png"})], "tool_use"),
                                 turn([("text", "SEEN IT")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    row = f"PNG · 3×2 · {len(picture)} B"
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"look at the shot\r")
        terminal.until(lambda: "SEEN IT" in terminal.text())
        check(f"the read tool's picture shows as a row in its block: {row}", row in terminal.text())
        terminal.send(b"/quit\r")
        terminal.close()
        terminal = probe.Terminal(project, environment, rows=40, resume=True)
        terminal.until(lambda: "SEEN IT" in terminal.text())
        check("and again in the session resumed", row in terminal.text())
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
