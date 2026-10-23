#!/usr/bin/env python3
"""Probe the status line's job count and its list through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-runners.py .build/release/ask

A real background job (a loopback http.server the fake model starts, waits on and later stops) is counted, listed by a click on the
count and by /tasks, and leaves the count when the model stops it. No window, real credentials or host clipboard writes.
"""
import importlib.util
import json
import os
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


def status_row(terminal):
    return next(index for index, line in enumerate(terminal.screen.display) if "· ready" in line or "working…" in line)


def click_count(terminal, label):
    row = status_row(terminal)
    column = terminal.screen.display[row].index(label)
    terminal.draw(lambda: terminal.send(f"\x1b[<0;{column + 2};{row + 1}M\x1b[<0;{column + 2};{row + 1}m".encode()))


def main():
    port = probe.agent.free_port()
    command = f"exec python3 -m http.server {port} --bind 127.0.0.1"
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("call", "t1", "bash", {"command": command, "yield_seconds": 1})], "tool_use"),
            turn([("call", "t2", "wait", {"job": "job-1", "port_open": port, "timeout_seconds": 20})], "tool_use"),
            turn([("text", "Serving.")], "end_turn"),
            turn([("call", "t3", "job_stop", {"job": "job-1"})], "tool_use"),
            turn([("text", "Stopped.")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            check("with nothing running the status line has no count", "job" not in terminal.screen.display[28])
            start = len(terminal.raw)
            terminal.send(b"Serve\r")
            terminal.until(lambda: b"Serving." in bytes(terminal.raw)[start:] and b"ready" in bytes(terminal.raw)[start:])
            terminal.repaint()
            check("a running job is counted in the status line", "ready · 1 job" in terminal.text())
            click_count(terminal, "1 job")
            check("a click on the count opens the list of what runs", "job-1  " + command in terminal.text()
                  and terminal.screen.display[status_row(terminal) - 1].startswith("job-1  exec python3"))
            click_count(terminal, "1 job")
            check("another click closes it", "job-1  exec" not in terminal.text())
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            check("/tasks opens it as well", "job-1  exec" in terminal.text())
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            check("and closes it", terminal.text().count("job-1  exec") == 0)
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            start = len(terminal.raw)
            terminal.send(b"Stop it\r")
            terminal.until(lambda: b"Stopped." in bytes(terminal.raw)[start:] and b"ready" in bytes(terminal.raw)[start:])
            terminal.repaint()
            check("when the model stops the job the count and the open list go", "1 job" not in terminal.text()
                  and "job-1  exec" not in terminal.text())
            check("the job itself is gone", not probe.agent.accepts(port))
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.send(b"/quit\r")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and probe.agent.accepts(port):
                    time.sleep(0.1)
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
