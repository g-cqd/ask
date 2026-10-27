#!/usr/bin/env python3
"""Real bash job + scripted provider + PTY: idle progress, strip spacing, input and focus.

ASK_PYTE=/tmp/ask-pty/lib python3 Scripts/probe-job-progress.py .build/release/ask
Uses pyte for position-addressed frames; forces a full repaint after transcript changes
because pyte does not implement regional scrolling. Not a physical-terminal claim.
"""
import importlib.util
import json
import os
import re
import select
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def check(label, condition):
    probe.check(label, condition)


def status_row(terminal):
    return next(i for i, line in enumerate(terminal.screen.display) if "1 job" in line)


def click(terminal, row, column):
    terminal.draw(lambda: terminal.send(
        f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode()))


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"prompt": "ask> ", "separator": "off", "tint": "off",
                              "padding": "off", "localizedDurations": "off", "spinner": "line"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("call", "t1", "bash", {"command": "printf 'JOB READY\\n'; exec sleep 60",
                                          "yield_seconds": 1})], "tool_use"),
            turn([("text", "JOB RUNNING")], "end_turn"),
            turn([("call", "t2", "job_stop", {"job": "job-1"})], "tool_use"),
            turn([("text", "JOB STOPPED")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=100, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Start\r")
            terminal.until(lambda: b"JOB RUNNING" in terminal.raw and "1 job" in terminal.text())
            terminal.repaint()
            row = status_row(terminal)
            column = terminal.screen.display[row].index("1 job")
            click(terminal, row, column)
            row = status_row(terminal)
            check("one blank row separates status and jobs", not terminal.screen.display[row + 1].strip()
                  and terminal.screen.display[row + 2].startswith("job-1  "))
            check("input remains above status", terminal.screen.display[row - 1].startswith("ask>"))
            line = terminal.screen.display[-1]
            check("single cell spinner occupies the trailing column", line[-1] in "|/-\\")
            before = line[-1]
            terminal.until(lambda: terminal.screen.display[-1][-1] != before)
            check("job spinner animates without another model turn", terminal.screen.display[-1][-1] in "|/-\\")
            terminal.until(lambda: bool(re.search(r"\s[2-9][0-9]* [|/\\-]$", terminal.screen.display[-1])))
            check("job duration advances while model is idle", bool(re.search(
                r"\s[2-9][0-9]* [|/\\-]$", terminal.screen.display[-1])))
            terminal.draw(lambda: terminal.send(b"draft"))
            row = status_row(terminal) - 1
            click(terminal, row, 5)
            terminal.draw(lambda: terminal.send(b"X"))
            check("moved input retains correct click geometry", "ask> Xdraft" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x03"))
            terminal.draw(lambda: terminal.send(b"\x1b[B"))
            terminal.draw(lambda: terminal.send(b"\r"))
            terminal.until(lambda: "JOB READY" in terminal.text())
            check("job row focuses its original output", "main › job-1" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x1b"))
            terminal.draw(lambda: terminal.send(b"Stop\r"))
            terminal.until(lambda: b"JOB STOPPED" in terminal.raw and "1 job" not in terminal.text())
            terminal.repaint()
            check("ending the job removes its strip and gap", terminal.screen.display[-2].startswith("ask>")
                  and "job-1  " not in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.send(b"/quit\r")
                # Let /quit stop children before the harness's forced-cleanup fallback.
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if select.select([terminal.fd], [], [], 0.1)[0]:
                        try:
                            if not os.read(terminal.fd, 65536):
                                break
                        except OSError:
                            break
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
