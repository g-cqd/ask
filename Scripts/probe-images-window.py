#!/usr/bin/env python3
"""Pictures sent to the terminal only while they are near the view (roadmap 0208), through the real binary, a PTY and a fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-images-window.py .build/release/ask

The model reads a PNG, then twelve more exchanges push it far above the view. Resumed as Ghostty, the session sends no picture
while its block is that far up; scrolled back to the top, the picture is sent then, and its cells drawn. Hermetic: a picture made
here, no window or credentials.
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_images", os.path.join(HERE, "probe-images.py"))
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)
probe = images.probe
TURNS = 12


def main():
    check = probe.check
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-images-window-")
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    with open(os.path.join(project, "shot.png"), "wb") as file:
        file.write(images.png(3, 2))
    turn = probe.agent.turn
    script = [turn([("call", "r1", "read", {"path": "shot.png"})], "tool_use"), turn([("text", "SEEN IT")], "end_turn")]
    script += [turn([("text", f"ANSWER {n}")], "end_turn") for n in range(TURNS)]
    server = probe.agent.Server(script)
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"look at the shot\r")
        terminal.until(lambda: "SEEN IT" in terminal.text())
        for n in range(TURNS):
            terminal.send(f"question {n}\r".encode())
            terminal.until(lambda n=n: f"ANSWER {n}" in terminal.text())
        terminal.send(b"/quit\r")
        terminal.close()
        terminal = probe.Terminal(project, environment, rows=40, resume=True)
        terminal.until(lambda: "ask>" in terminal.text() and f"ANSWER {TURNS - 1}" in terminal.text())
        images.with_pixels(terminal)
        images.answer_graphics_query(terminal)
        deadline = probe.time.monotonic() + 2
        while probe.time.monotonic() < deadline:
            terminal.pump()
        check("resumed, a picture far above the view is not sent", b"a=t" not in bytes(terminal.raw))
        for _ in range(20):
            terminal.send(b"\x1b[5~")
            for _ in range(3):
                terminal.pump()
        terminal.until(lambda: b"a=t" in bytes(terminal.raw))
        check("scrolled back to it, it is sent", b"f=100" in bytes(terminal.raw))
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
