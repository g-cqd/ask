#!/usr/bin/env python3
"""Probe the status count and the runner strip below the status with real jobs in a PTY and a local fake provider.

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
    """The status: the row naming the model. Below it, after a blank row, the strip of jobs; above it, the input."""
    return next(index for index, line in enumerate(terminal.screen.display) if "anthropic/" in line)


def idle(terminal):
    return terminal.screen.display[status_row(terminal)].startswith("\u2713 \u00b7")


def strip(terminal):
    """The strip's rows: a job's label, two spaces, its command."""
    return [line.rstrip() for line in terminal.screen.display[status_row(terminal) + 1:] if line.startswith("[#")]


def click_count(terminal, label):
    row = status_row(terminal)
    column = terminal.screen.display[row].index(label)
    terminal.draw(lambda: terminal.send(f"\x1b[<0;{column + 2};{row + 1}M\x1b[<0;{column + 2};{row + 1}m".encode()))


def main():
    port = probe.agent.free_port()
    command = f"exec python3 -u -m http.server {port} --bind 127.0.0.1"
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "separator": "off", "tint": "off", "padding": "off", "durations": "clock"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("call", "t1", "bash", {"command": command, "yield_seconds": 1})], "tool_use"),
            turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_port": port, "timeout_seconds": 20})], "tool_use"),
            turn([("text", "Serving.")], "end_turn"),
            turn([("call", "t3", "job", {"job": "job-1", "action": "stop"})], "tool_use"),
            turn([("text", "Stopped.")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=30)
            # The input is drawn before the status line names the model.
            terminal.until(lambda: "ask>" in terminal.text() and "anthropic/" in terminal.text())
            check("with nothing running the status line has no count", "job" not in terminal.screen.display[status_row(terminal)])
            start = len(terminal.raw)
            terminal.send(b"Serve\r")
            terminal.until(lambda: b"Serving." in bytes(terminal.raw)[start:] and idle(terminal))
            terminal.repaint()
            check("a running job is counted in the status line", terminal.screen.display[status_row(terminal)].rstrip().endswith("· 1 job"))
            click_count(terminal, "1 job")
            jobs = strip(terminal)
            check("a click on the count opens the strip below the status, after a blank row",
                  len(jobs) == 1 and command in jobs[0] and not terminal.screen.display[status_row(terminal) + 1].strip()
                  and terminal.screen.display[status_row(terminal) - 1].startswith("ask>"))
            label = jobs[0].split()[0] if jobs else "[#?]"
            check("the strip states what the job is doing", "· running" in terminal.screen.display[-1])
            click_count(terminal, "1 job")
            check("another click closes it", not strip(terminal))
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            check("/tasks opens it as well", len(strip(terminal)) == 1)
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            check("and closes it", not strip(terminal))
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            terminal.draw(lambda: terminal.send(b"draft"))
            row = status_row(terminal) - 1
            # Click the start of the draft in the input above the status, which moved up for the strip.
            terminal.draw(lambda: terminal.send(f"\x1b[<0;6;{row + 1}M\x1b[<0;6;{row + 1}m".encode()))
            terminal.draw(lambda: terminal.send(b"X"))
            check("the moved input is still clickable at the displayed cell", "ask> Xdraft" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x1b"))
            check("Esc closes the strip and keeps the draft", not strip(terminal)
                  and terminal.screen.display[status_row(terminal) - 1].startswith("ask> Xdraft"))
            terminal.draw(lambda: terminal.send(b"\x18/tasks\r"))
            terminal.draw(lambda: terminal.send(b"\x1b[B"))
            terminal.draw(lambda: terminal.send(b"\r"))
            terminal.until(lambda: "Serving HTTP on" in terminal.text())
            check("Down then Enter shows the job's real output in place of the conversation",
                  "Serving HTTP on" in terminal.text() and "Serving." not in terminal.text())
            check("the status line says which lane is shown", f"main › {label} · esc returns" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x1b"))
            check("Esc returns to the conversation, with the strip still open",
                  "Serving." in terminal.text() and "Serving HTTP on" not in terminal.text() and len(strip(terminal)) == 1)
            terminal.draw(lambda: terminal.send(b"\x18/tasks\r"))
            start = len(terminal.raw)
            terminal.send(b"Stop it\r")
            terminal.until(lambda: b"Stopped." in bytes(terminal.raw)[start:] and idle(terminal) and "1 job" not in terminal.text())
            terminal.repaint()
            check("when the model stops the job the count and the open list go", "1 job" not in terminal.text() and not strip(terminal))
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
