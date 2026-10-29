#!/usr/bin/env python3
"""Probe the runner sidebar through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-sidebar.py .build/release/ask

`ui.sidebar: "open"` opens it at start. A real background job (a loopback http.server the fake model starts and later stops) appears in it, a click on its row
shows what it printed in place of the conversation, Esc returns, and Ctrl+\\ closes and opens the panel. No window, credentials or clipboard.
"""
import importlib.util
import os
import re
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


def divider_column(terminal):
    line = terminal.screen.display[0]
    return line.index("│") if "│" in line else None


def status_row(terminal):
    """The status: the row naming the model, the last of the screen."""
    return next(index for index, line in enumerate(terminal.screen.display) if "anthropic/" in line)


def idle(terminal):
    return terminal.screen.display[status_row(terminal)].startswith("\u2713 \u00b7")


def listed(terminal):
    """Whether the sidebar's first row lists a job: its label, two spaces, and its command, cut to what the elapsed time leaves."""
    return bool(re.search(r"│ \[#[0-9a-f]{4}\]  e", terminal.screen.display[0]))


def main():
    port = probe.agent.free_port()
    command = f"exec python3 -u -m http.server {port} --bind 127.0.0.1"
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write("{ ui: { sidebar: 'open', prompt: 'ask> ' } }")
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
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.repaint()
            check("open from the configuration, with no runners it says so", "no runners" in terminal.screen.display[0])
            divider = divider_column(terminal)
            check("the divider is in every transcript row", divider is not None
                  and all(terminal.screen.display[row][divider] == "│" for row in range(0, 26)))
            start = len(terminal.raw)
            terminal.send(b"Serve\r")
            terminal.until(lambda: b"Serving." in bytes(terminal.raw)[start:] and idle(terminal))
            terminal.repaint()
            check("a running job is listed in the sidebar", listed(terminal))
            row = status_row(terminal)
            check("the status line and the input keep the whole width", terminal.screen.display[row].rstrip().endswith("· 1 job")
                  and terminal.screen.display[row - 2].startswith("ask>") and "│" not in terminal.screen.display[row - 2]
                  and set(terminal.screen.display[row - 1]) == {"─"} and set(terminal.screen.display[row - 3]) == {"─"})
            terminal.draw(lambda: terminal.send(b"\x1c"))
            check("Ctrl+\\ closes it and the width comes back", divider_column(terminal) is None and not listed(terminal))
            terminal.draw(lambda: terminal.send(b"\x1c"))
            check("and opens it again", divider_column(terminal) == divider and listed(terminal))
            column = divider + 4
            terminal.draw(lambda: terminal.send(f"\x1b[<0;{column + 1};1M\x1b[<0;{column + 1};1m".encode()))
            terminal.until(lambda: "Serving HTTP on" in terminal.text())
            check("a click on its row shows what the job printed in place of the conversation",
                  "Serving HTTP on" in terminal.text() and "Serving." not in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x1b"))
            check("Esc returns to the conversation, the sidebar still open", "Serving." in terminal.text()
                  and listed(terminal))
            start = len(terminal.raw)
            terminal.send(b"Stop it\r")
            terminal.until(lambda: b"Stopped." in bytes(terminal.raw)[start:] and idle(terminal))
            terminal.repaint()
            check("when the job stops it leaves the sidebar", "no runners" in terminal.screen.display[0])
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
