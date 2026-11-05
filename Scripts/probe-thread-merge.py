#!/usr/bin/env python3
"""Probe `/merge` (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-merge.py .build/release/ask

A thread that is stopped and not merged back (No to the question) never merges on its own: `/merge` in its lane merges it, with a
summary request, and main shows the merge. While it works, `/merge` is refused. Hermetic: no window, credentials or clipboard.
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


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            threads = {"names": "numbered", "summaryInstructions": "PROBE-EXTRA: name every file."}
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": threads}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("tool", "c1", "sleep 30")], "tool_use"),        # 0 thread-1, at work
            turn([("text", "MERGED SUMMARY")], "end_turn"),        # 1 its summary, once merged by hand
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/thread one task\r")
            terminal.until(lambda: "started here · one task" in terminal.text() and len(server.requests) > 0)
            runners.open_lane(terminal, "thread-1")
            terminal.send(b"/merge\r")
            terminal.until(lambda: "still working" in terminal.text())
            check("/merge while it works is refused", "Ctrl+C" in terminal.text() and len(server.requests) == 1)
            terminal.send(b"\x03")
            terminal.until(lambda: "Merge it back" in terminal.text())
            terminal.send(b"\x1b")  # No: kept stopped and unmerged
            terminal.until(lambda: "Merge it back" not in terminal.text() and runners.state(terminal, "thread-1") == "stopped")
            check("No keeps it stopped, unmerged", runners.state(terminal, "thread-1") == "stopped"
                  and len(server.requests) == 1)
            terminal.send(b"/merge\r")
            terminal.until(lambda: len(server.requests) > 1)
            time.sleep(0.5)
            asked = json.dumps(server.requests[1]["body"])
            check("/merge merges it, with a summary request", "merging back" in asked)
            check("which carries threads.summaryInstructions after the standard instruction",
                  asked.find("PROBE-EXTRA: name every file.") > asked.find("merging back") > -1)
            terminal.send(b"\x1b")
            terminal.until(lambda: "merged · one task" in terminal.text())
            check("and main shows the merge", "thread-1 · merged · one task" in terminal.text())
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
