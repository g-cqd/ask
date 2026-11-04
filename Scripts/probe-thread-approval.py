#!/usr/bin/env python3
"""Probe a thread's approval question (roadmap 0195) through the real binary, a PTY and a local fake provider, with approvals on.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-approval.py .build/release/ask

A thread's command asks for permission. The question is the thread's: main never shows it, the thread is listed as waiting for approval
and stays so after main's turn has ended, its lane shows the question, and an answer there lets the command run and the thread finish;
main's next message then carries its answer. Hermetic: no window, credentials or clipboard.
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
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "MAIN ONE")], "end_turn"),
            turn([("tool", "c1", "touch thread.txt")], "tool_use"),
            turn([("text", "THREAD DONE")], "end_turn"),
            turn([("text", "MAIN TWO")], "end_turn"),
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        made = os.path.join(project, "thread.txt")
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=34, approvals=True)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"hello\r")
            terminal.until(lambda: "MAIN ONE" in terminal.text())
            terminal.send(b"/thread make a file\r")
            terminal.until(lambda: "Started thread-1" in terminal.text())
            time.sleep(1)
            terminal.send(b"/jobs\r")
            terminal.until(lambda: "waiting for approval" in terminal.text())
            check("the thread is listed as waiting for approval, and main does not ask",
                  "thread-1  make a file · waiting for approval" in terminal.text() and "Allow it?" not in terminal.text())
            time.sleep(3)
            terminal.repaint()
            check("main idle, the question is not declined: it still waits and nothing ran",
                  "waiting for approval" in terminal.text() and not os.path.exists(made))
            terminal.send(b"\x1b[B")
            time.sleep(0.3)
            terminal.send(b"\r")
            terminal.until(lambda: "Allow it?" in terminal.text())
            check("its lane shows the question", "Allow it?" in terminal.text() and "touch thread.txt" in terminal.text())
            terminal.send(b"\r")
            terminal.until(lambda: "THREAD DONE" in terminal.text())
            check("answered there, the command runs and the thread finishes", os.path.exists(made))
            terminal.send(b"\x1b")
            terminal.until(lambda: "back to the conversation" not in terminal.text())
            terminal.send(b"next\r")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            sent = json.dumps(server.requests[3]["body"]) if len(server.requests) > 3 else ""
            check("main's next message carries the thread's answer", "--- thread thread-1 ---" in sent and "THREAD DONE" in sent)
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
