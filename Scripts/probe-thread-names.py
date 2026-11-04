#!/usr/bin/env python3
"""Probe the threads settings, `/rename` and `/threads` (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-names.py .build/release/ask

With `threads.max` 1 and `threads.depth` 1, a second thread while one works is refused, and so is a thread inside a thread. `/rename`
in a thread's lane names it in the list, and the name comes back after `ask --continue`. `/threads` lists the session's threads and
`/threads NAME` opens one's lane. Names are numbered here: the on-device model is not asked. Hermetic.
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


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"max": 1, "depth": 1, "names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("tool", "c1", "sleep 30")], "tool_use"),   # 0 thread-1, at work
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/thread first task\r")
            terminal.until(lambda: "started here · first task" in terminal.text() and len(server.requests) > 0)
            terminal.send(b"/thread second task\r")
            terminal.until(lambda: "threads.max" in terminal.text())
            check("with threads.max 1, a second thread while one works is refused",
                  "as many as threads.max allows" in terminal.text() and len(server.requests) == 1)
            terminal.send(b"/threads thread-1\r")
            terminal.until(lambda: "main  back to the conversation" in terminal.text())
            check("/threads NAME opens the thread's lane", "first task" in terminal.text())
            status = next(line for line in terminal.screen.display if "anthropic/" in line)
            check("in its lane the status mark spins for the working thread (main is idle)", not status.startswith("\u2713"))
            terminal.send(b"/thread deeper\r")
            terminal.until(lambda: "threads.depth" in terminal.text())
            check("with threads.depth 1, a thread inside a thread is refused", "nest at most 1 deep" in terminal.text())
            terminal.send(b"/rename parser work\r")
            terminal.until(lambda: "parser work  first task" in terminal.text())
            check("/rename in the lane names the thread in the list", "parser work  first task" in terminal.text()
                  and terminal.screen.display[0].strip() != "")
            terminal.send(b"\x1b")
            terminal.until(lambda: "back to the conversation" not in terminal.text())
            terminal.send(b"/threads\r")
            terminal.until(lambda: "parser work" in terminal.text() and "running · first task" in terminal.text())
            check("/threads lists the session's threads, by name, state and task", "running · first task" in terminal.text())
            terminal.send(b"\x15\x1b")
            terminal.send(b"/quit\r")
            terminal.close()
            terminal = probe.Terminal(project, environment, rows=40, resume=True)
            terminal.until(lambda: "started here · first task" in terminal.text())
            terminal.send(b"/jobs\r")
            terminal.until(lambda: "first task" in terminal.text() and "stopped" in terminal.text())
            check("the name comes back after a resume", "parser work  first task · stopped" in terminal.text())
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
