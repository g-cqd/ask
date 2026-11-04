#!/usr/bin/env python3
"""Probe stopping threads (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-stop.py .build/release/ask

A thread started before any prompt is recorded in main's session. Ctrl+C in its lane stops it and the thread under it, and asks once
whether to merge them back; yes merges them from the bottom up. `/new` while a thread works asks first: no stays, yes switches and
leaves it unmerged. Hermetic: no window, credentials or clipboard.
"""
import glob
import importlib.util
import json
import os
import re
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import probe_runner_list as runners  # noqa: E402
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def body(server, index):
    return json.dumps(server.requests[index]["body"]) if len(server.requests) > index else ""



def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("tool", "c1", "sleep 30")], "tool_use"),   # 0 thread-1
            turn([("tool", "c2", "sleep 30")], "tool_use"),   # 1 thread-2, under it
            turn([("text", "SUMMARY TWO")], "end_turn"),      # 2 thread-2 merges first
            turn([("text", "SUMMARY ONE")], "end_turn"),      # 3 then thread-1
            turn([("tool", "c3", "sleep 30")], "tool_use"),   # 4 thread-3, at work during /new
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/thread early task\r")
            terminal.until(lambda: "started here · early task" in terminal.text() and len(server.requests) > 0)
            mains = [p for p in glob.glob(state + "/ask/sessions/*/*.jsonl") if '"event":"started"' in open(p).read()]
            check("a thread started before any prompt is recorded in main's session", len(mains) == 1)
            runners.show(terminal)
            job_under = re.compile(r"^[│ ] [├└] \S+ #[0-9a-f]{4} sleep 30")
            terminal.until(lambda: any(job_under.match(line) for line in runners.lines(terminal)))
            check("the command the thread runs is listed under it",
                  any(job_under.match(line) for line in runners.lines(terminal)))
            runners.open_lane(terminal, "thread-1")
            terminal.send(b"/thread nested task\r")
            terminal.until(lambda: len(server.requests) > 1)
            time.sleep(0.5)
            terminal.send(b"\x03")
            terminal.until(lambda: "Allow it?" in terminal.text() or "Merge them back" in terminal.text())
            check("Ctrl+C in its lane stops it and the thread under it, and asks once",
                  "thread-1 and its 1 thread were stopped" in terminal.text() and len(server.requests) == 2)
            terminal.send(b"y")  # a confirmation starts on No
            time.sleep(0.2)
            terminal.send(b"\r")
            terminal.until(lambda: len(server.requests) > 3)
            time.sleep(0.5)
            check("yes merges them from the bottom up: the inner one's summary goes into the outer one's",
                  "merging back" in body(server, 2) and "nested task" in body(server, 2)
                  and "SUMMARY TWO" in body(server, 3))
            terminal.send(b"\x1b")
            terminal.until(lambda: "merged · early task" in terminal.text())
            check("and main shows the outer one merged", "thread-1 · merged · early task" in terminal.text())
            terminal.send(b"/thread third task\r")
            terminal.until(lambda: len(server.requests) > 4)
            time.sleep(0.5)
            terminal.send(b"/new\r")
            terminal.until(lambda: "still working" in terminal.text())
            check("/new while a thread works asks first", "thread-3 is still working" in terminal.text())
            terminal.send(b"\x1b")
            time.sleep(1)
            terminal.repaint()
            check("no stays in the session", "merged · early task" in terminal.text() and "thread-3" in terminal.text()
                  and "still working" not in terminal.text())
            terminal.send(b"/new\r")
            terminal.until(lambda: "still working" in terminal.text())
            terminal.send(b"y")
            time.sleep(0.2)
            terminal.send(b"\r")
            began = time.monotonic()
            while time.monotonic() - began < 40 and runners.row(terminal, "thread-3") is not None:
                terminal.pump()
            terminal.repaint()
            check("yes switches, the thread stopped and left unmerged in the old session",
                  "thread-3" not in terminal.text() and len(server.requests) == 5)
        except (AssertionError, StopIteration):
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
