#!/usr/bin/env python3
"""Probe `threads.merge` "ask" (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-merge-ask.py .build/release/ask

A thread that finished asks whether to merge, in main (threads.questions focus). No leaves it unmerged, marked ○, with no summary
written; `/merge` in its lane merges it later. Yes merges the next one at once. Hermetic.
"""
import importlib.util
import json
import os
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


def summaries(server):
    return [r for r in server.requests if "merging back" in json.dumps(r["body"])]


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered", "merge": "ask"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "DONE ONE")], "end_turn"),       # 0 thread-1
            turn([("text", "SUMMARY ONE")], "end_turn"),    # 1 its summary, after /merge
            turn([("text", "DONE TWO")], "end_turn"),       # 2 thread-2
            turn([("text", "SUMMARY TWO")], "end_turn"),    # 3 its summary, after yes
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
            terminal.until(lambda: "thread-1 finished" in terminal.text())
            check("a finished thread asks, in main, whether to merge",
                  "Merge it back into main" in terminal.text() and not summaries(server))
            terminal.send(b"\x1b")  # No
            terminal.until(lambda: "Merge it back" not in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.mark_of(terminal, "first task") == "○")
            time.sleep(0.5)
            check("No leaves it unmerged and idle, ○, with no summary written",
                  runners.mark_of(terminal, "first task") == "○" and not summaries(server))
            runners.open_thread(terminal, "thread-1")
            terminal.send(b"/merge\r")
            terminal.until(lambda: len(summaries(server)) == 1)
            terminal.send(b"\x1b")
            terminal.until(lambda: "merged · first task" in terminal.text())
            check("/merge in its lane merges it later", "thread-1 · merged · first task" in terminal.text())
            terminal.send(b"/thread second task\r")
            terminal.until(lambda: "thread-2 finished" in terminal.text())
            terminal.send(b"y\r")
            terminal.until(lambda: "merged · second task" in terminal.text())
            check("Yes merges the next at once", len(summaries(server)) == 2)
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
