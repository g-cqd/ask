#!/usr/bin/env python3
"""Probe the list's marks for running threads and jobs (roadmap 0195, note n15) through the real binary, a PTY and a local fake
provider.

Scripts/probe-runner-marks.py .build/release/ask

A thread waits on a quiet `sleep 30`: once three seconds pass with nothing from either, the thread is marked ◇ and its job $. Main's
command prints every half second: its job keeps spinning, its output reported to the screen by the job table. Hermetic.
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
SPINNER = set("|/-\\●⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷⠁⠂⠄⠈⠐⠠⢀⡀")
TICKS = "for i in $(seq 120); do echo tick $i; sleep 0.5; done"


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "spinner": "line"}, "threads": {"names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("tool", "c1", "sleep 30")], "tool_use"),   # the thread's
            turn([("tool", "c2", TICKS)], "tool_use"),        # main's
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/thread wait a while\r")
            terminal.until(lambda: "started here" in terminal.text() and len(server.requests) >= 1)
            terminal.send(b"count\r")
            terminal.until(lambda: len(server.requests) >= 2)
            terminal.until(lambda: "1 thread" in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.mark_of(terminal, "sleep 30") == "$")
            time.sleep(1.5)
            terminal.repaint()
            check("the thread waiting on a quiet command is marked ◇", runners.mark_of(terminal, "wait a while") == "◇")
            check("its quiet job is marked $", runners.mark_of(terminal, "sleep 30") == "$")
            seen = set()
            for _ in range(8):
                time.sleep(0.5)
                terminal.repaint()  # pyte keeps a row's old frame through partial redraws
                seen.add(runners.mark_of(terminal, "seq 120"))
            check("main's job, writing all along, keeps spinning", seen and seen <= SPINNER and len(seen) > 1)
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
