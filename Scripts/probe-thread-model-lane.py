#!/usr/bin/env python3
"""Probe `/model` in a thread's lane (owner, 2026-11-26 and 2026-11-27) through the real binary, a PTY and a local fake provider.

Scripts/probe-thread-model-lane.py .build/release/ask

In a thread's lane, `/model MODEL` gives that thread its model: its next request goes to it, the lane stays, and main's next
request keeps main's model. Hermetic.
"""
import importlib.util
import json
import os
import sys
import tempfile

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
    turn = probe.agent.turn
    root = tempfile.mkdtemp()
    project, config, state = root + "/project", root + "/config", root + "/state"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}}, file)
    server = probe.agent.Server([
        turn([("text", "MAIN ONE")], "end_turn"),
        turn([("text", "THREAD ONE")], "end_turn"),
        turn([("text", "THREAD TWO")], "end_turn"),
        turn([("text", "MAIN TWO")], "end_turn"),
    ])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
        environment.pop(key, None)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"hello\r")
        terminal.until(lambda: "MAIN ONE" in terminal.text())
        terminal.send(b"/thread look around\r")
        terminal.until(lambda: "thread-1 · started here" in terminal.text())
        runners.show(terminal)
        terminal.until(lambda: runners.state(terminal, "thread-1") == "idle")
        runners.open_lane(terminal, "thread-1")
        terminal.until(lambda: "THREAD ONE" in terminal.text())
        main_model = server.requests[0]["body"].get("model")

        terminal.send(b"/model claude-probe-lane\r")
        terminal.until(lambda: "main keeps its model" in terminal.text())
        check("in a thread's lane, /model answers for the thread", "thread-1 works with" in terminal.text())
        terminal.send(b"again\r")
        terminal.until(lambda: "THREAD TWO" in terminal.text())
        check("the thread's next request goes to the model chosen there",
              server.requests[2]["body"].get("model") == "claude-probe-lane")
        check("and the lane stayed the thread's", "MAIN ONE" not in terminal.text().split("THREAD ONE")[-1])

        terminal.send(b"\x1b")
        terminal.until(lambda: "MAIN ONE" in terminal.text())
        terminal.send(b"main again\r")
        terminal.until(lambda: "MAIN TWO" in terminal.text())
        check("main's next request keeps main's model", server.requests[3]["body"].get("model") == main_model)
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
