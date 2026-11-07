#!/usr/bin/env python3
"""Probe that a thread merges only by `/merge` (note n52, roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-merge-manual.py .build/release/ask

The file still sets the retired `threads.merge` ("auto", then "ask"): ask opens. A thread that finished asks nothing, in main or in its
lane, and stays unmerged, marked ○, with no summary written; `/merge` in its lane merges it. Hermetic.
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


def run(retired):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered", "merge": retired}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "DONE ONE")], "end_turn"),       # 0 thread-1
            turn([("text", "SUMMARY ONE")], "end_turn"),    # 1 its summary, after /merge
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            check(f'merge "{retired}": a file that sets the retired key opens', "Invalid" not in terminal.text())
            terminal.send(b"/thread first task\r")
            terminal.until(lambda: "thread-1 · started here" in terminal.text() and len(server.requests) == 1)
            time.sleep(0.5)
            runners.show(terminal)
            terminal.until(lambda: runners.mark_of(terminal, "first task") == "○")
            time.sleep(2)
            terminal.repaint()
            check(f'merge "{retired}": a finished thread asks nothing and stays unmerged, ○, with no summary written',
                  runners.mark_of(terminal, "first task") == "○" and "Merge it back" not in terminal.text()
                  and not summaries(server))
            runners.open_lane(terminal, "thread-1")
            check(f'merge "{retired}": nor in its lane', "Merge it back" not in terminal.text())
            terminal.send(b"/merge\r")
            terminal.until(lambda: len(summaries(server)) == 1)
            terminal.send(b"\x1b")
            terminal.until(lambda: "merged · first task" in terminal.text())
            check(f'merge "{retired}": /merge in its lane merges it', "thread-1 · merged · first task" in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def main():
    run("auto")
    run("ask")
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
