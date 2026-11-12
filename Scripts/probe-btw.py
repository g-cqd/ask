#!/usr/bin/env python3
"""Probe `/btw` (roadmap 0194) through the real binary, a PTY and a local fake provider.

Scripts/probe-btw.py .build/release/ask

While a turn runs a command, `/btw` asks beside it: its answer appears in a block of its own while the turn goes on, the turn then ends as
it would have, the aside's request carries the question and ask's instruction, and the session file holds no trace of the aside.
Hermetic: no window, credentials or clipboard.
"""
import glob
import importlib.util
import json
import os
import sys
import tempfile

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
            json.dump({"ui": {"inputPrefix": "ask> "}, "approvals": {"allow": ["commands"]}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("tool", "t1", "sleep 3")], "tool_use"),
            turn([("text", "ASIDE ANSWER")], "end_turn"),
            turn([("text", "TURN DONE")], "end_turn"),
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"do it\r")
            terminal.until(lambda: "sleep 3" in terminal.text())
            terminal.send(b"/btw why sleep?\r")
            terminal.until(lambda: "ASIDE ANSWER" in terminal.text())
            check("the aside's answer appears while the turn runs", "TURN DONE" not in terminal.text())
            check("in a block headed by the question", "why sleep?" in terminal.text())
            terminal.until(lambda: "TURN DONE" in terminal.text())
            check("the turn then ends as it would have", "TURN DONE" in terminal.text())
            asked = json.dumps(server.requests[1]["body"]["messages"][-1]) if len(server.requests) > 1 else ""
            check("the aside's request carries the question and ask's instruction", "why sleep?" in asked and "aside" in asked)
            sessions = glob.glob(state + "/ask/sessions/*/*.jsonl")
            recorded = open(sessions[0]).read() if sessions else ""
            check("the session holds no trace of the aside", sessions and "ASIDE ANSWER" not in recorded and "why sleep" not in recorded)
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
