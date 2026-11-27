#!/usr/bin/env python3
"""Probe where another model answers, and a thread's own model across a resume (owner, 2026-11-27), through the real binary, a PTY and
a local fake provider.

Scripts/probe-model-change.py .build/release/ask

`/model` in main: a gray line says the new model answers from there, before its reply. `/model` in a thread's lane: the same line in
the lane, and after `ask --continue` the thread's next request still goes to its own model, while main keeps main's. Hermetic.
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
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "MAIN ONE")], "end_turn"),         # 0 main, first model
            turn([("text", "MAIN TWO")], "end_turn"),         # 1 main, after /model
            turn([("text", "THREAD ONE")], "end_turn"),       # 2 thread-1, main's model
            turn([("text", "THREAD TWO")], "end_turn"),       # 3 thread-1, after /model in its lane
            turn([("text", "THREAD THREE")], "end_turn"),     # 4 thread-1, after the resume
            turn([("text", "MAIN THREE")], "end_turn"),       # 5 main, after the resume
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
            check("the first model of a conversation is no change", "answers from here" not in terminal.text())
            terminal.send(b"/model claude-probe-main\r")
            terminal.until(lambda: "For this run: claude-probe-main" in terminal.text())
            # /model offers /thinking next, in the input: cleared once it is there, so the next line is a prompt.
            terminal.until(lambda: "ask> /thinking" in terminal.text())
            terminal.send(b"\x15")
            terminal.until(lambda: "ask> /thinking" not in terminal.text())
            terminal.send(b"again\r")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            shown = terminal.text()
            check("in main, a gray line says where the new model answers from, before its reply",
                  "claude-probe-main answers from here." in shown
                  and shown.index("claude-probe-main answers from here.") < shown.index("MAIN TWO"))
            main_model = server.requests[1]["body"].get("model")

            terminal.send(b"/thread look around\r")
            terminal.until(lambda: "thread-1 · started here" in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.state(terminal, "thread-1") == "idle")
            runners.open_lane(terminal, "thread-1")
            terminal.until(lambda: "THREAD ONE" in terminal.text())
            terminal.send(b"/model claude-probe-thread\r")
            terminal.until(lambda: "main keeps its model" in terminal.text())
            terminal.send(b"\x15")
            terminal.send(b"on\r")
            terminal.until(lambda: "THREAD TWO" in terminal.text())
            lane = terminal.text()
            check("in the thread's lane, the same line, before the thread's reply",
                  "claude-probe-thread answers from here." in lane
                  and lane.index("claude-probe-thread answers from here.") < lane.index("THREAD TWO"))
            check("its request went to its model", server.requests[3]["body"].get("model") == "claude-probe-thread")
            terminal.send(b"\x1b")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            terminal.send(b"/quit\r")
            terminal.close()
            terminal = None

            terminal = probe.Terminal(project, environment, rows=40, resume=True)
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            check("after the resume, main still shows where its model changed",
                  "claude-probe-main answers from here." in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.row(terminal, "thread-1") is not None)
            runners.open_lane(terminal, "thread-1")
            terminal.until(lambda: "THREAD TWO" in terminal.text())
            check("the thread's lane still shows where its model changed",
                  "claude-probe-thread answers from here." in terminal.text())
            terminal.send(b"after resume\r")
            terminal.until(lambda: "THREAD THREE" in terminal.text())
            check("after the resume, the thread's next request goes to its own model",
                  server.requests[4]["body"].get("model") == "claude-probe-thread")
            terminal.send(b"\x1b")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            terminal.send(b"main after resume\r")
            terminal.until(lambda: "MAIN THREE" in terminal.text())
            check("and main's keeps main's", server.requests[5]["body"].get("model") == main_model)
        except (AssertionError, StopIteration, ValueError):
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
