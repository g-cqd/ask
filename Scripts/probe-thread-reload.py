#!/usr/bin/env python3
"""Probe `/reload` with a thread's lane shown (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-reload.py .build/release/ask

ask runs from a directory a build is installed into. A thread runs and merges; its lane is opened; a new build is installed and
`/reload` typed in the lane. The new process resumes the session and shows the same thread's lane again, its conversation drawn from
the thread's session. Hermetic: no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def install(directory):
    """A copy of the build, written beside and renamed into place, as a linker leaves a new build."""
    staged = os.path.join(directory, ".ask.new")
    shutil.copy2(probe.BINARY_SOURCE, staged)
    os.rename(staged, os.path.join(directory, "ask"))
    return os.path.join(directory, "ask")


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state, bin_dir = root + "/project", root + "/config", root + "/state", root + "/bin"
        for path in (project, config + "/ask", bin_dir):
            os.makedirs(path)
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        probe.BINARY_SOURCE = probe.BINARY
        probe.BINARY = install(bin_dir)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "MAIN ONE")], "end_turn"),
            turn([("text", "THREAD ANSWER")], "end_turn"),
            turn([("text", "THREAD SUMMARY")], "end_turn"),
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=34)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"hello\r")
            terminal.until(lambda: "MAIN ONE" in terminal.text())
            terminal.send(b"/thread look into X\r")
            terminal.until(lambda: "merged · look into X" in terminal.text())
            terminal.send(b"/jobs\r")
            terminal.until(lambda: "thread-1  look into X" in terminal.text())
            terminal.send(b"\x1b[B")
            time.sleep(0.3)
            terminal.send(b"\r")
            terminal.until(lambda: "main  back to the conversation" in terminal.text())
            check("the thread's lane is shown", "THREAD ANSWER" in terminal.text() and "MAIN ONE" not in terminal.text())
            time.sleep(1)
            install(bin_dir)
            time.sleep(2)
            terminal.send(b"/reload\r")
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline and "Reloaded ask" not in terminal.text() and "Resumed session" not in terminal.text():
                terminal.pump()
            terminal.until(lambda: "main  back to the conversation" in terminal.text() and "THREAD ANSWER" in terminal.text())
            check("after the reload the same thread's lane is shown again, drawn from its session",
                  "THREAD ANSWER" in terminal.text() and "MAIN ONE" not in terminal.text()
                  and "thread-1  look into X · merged" in terminal.text())
            terminal.send(b"\x1b")
            terminal.until(lambda: "MAIN ONE" in terminal.text() and "merged · look into X" in terminal.text())
            check("and main is there behind it", "thread-1 · merged · look into X" in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
