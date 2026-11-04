#!/usr/bin/env python3
"""Probe `/thread` (roadmap 0194) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread.py .build/release/ask

After one prompt, `/thread` forks the conversation and runs beside it: its request carries main's conversation; its answer is shown in
main; in its lane (/jobs, Down, Enter) what is typed goes to it and continues its own conversation; back in main, the next message takes
the threads' answers to the model, and main's session holds none of the thread's own words. Hermetic: no window, credentials or clipboard.
"""
import glob
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


def body(server, index):
    return json.dumps(server.requests[index]["body"]) if len(server.requests) > index else ""


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
            turn([("text", "THREAD ANSWER")], "end_turn"),
            turn([("text", "THREAD SECOND")], "end_turn"),
            turn([("text", "NESTED ANSWER")], "end_turn"),
            turn([("text", "MAIN TWO")], "end_turn"),
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=34)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"hello\r")
            terminal.until(lambda: "MAIN ONE" in terminal.text())
            terminal.send(b"/thread look into X\r")
            terminal.until(lambda: "THREAD ANSWER" in terminal.text())
            check("the thread's request carries main's conversation and its own task",
                  "hello" in body(server, 1) and "MAIN ONE" in body(server, 1) and "look into X" in body(server, 1))
            check("its answer is shown in main", "THREAD ANSWER" in terminal.text())
            terminal.until(lambda: "next message" in terminal.text())
            terminal.send(b"/jobs\r")
            terminal.until(lambda: "thread-1" in terminal.text())
            time.sleep(0.3)
            terminal.send(b"\x1b[B")
            time.sleep(0.3)
            terminal.send(b"\r")
            terminal.until(lambda: "main  back to the conversation" in terminal.text())
            shown = terminal.text()
            check("its lane shows its own conversation: its task, its answer, nothing of main's",
                  shown.count("look into X") >= 2 and "THREAD ANSWER" in shown and "MAIN ONE" not in shown)
            terminal.send(b"and Y?\r")
            terminal.until(lambda: "THREAD SECOND" in terminal.text())
            check("what is typed in the lane continues the thread",
                  "THREAD ANSWER" in body(server, 2) and "and Y?" in body(server, 2) and "MAIN ONE" in body(server, 2))
            terminal.send(b"/thread go deeper\r")
            terminal.until(lambda: "thread-2" in terminal.text() and len(server.requests) > 3)
            terminal.until(lambda: "thread-2  go deeper · done" in terminal.text())
            check("/thread in a thread's lane forks that thread, listed under it",
                  "and Y?" in body(server, 3) and "THREAD SECOND" in body(server, 3) and "go deeper" in body(server, 3)
                  and "  thread-2  go deeper" in terminal.text())
            terminal.send(b"\x1b")
            terminal.until(lambda: "back to the conversation" not in terminal.text())
            terminal.send(b"next\r")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            sent = body(server, 4)
            check("main's next message takes the threads' answers to the model",
                  "--- thread thread-1 ---" in sent and "THREAD ANSWER" in sent and "THREAD SECOND" in sent
                  and "--- thread thread-2 ---" in sent and "NESTED ANSWER" in sent)
            sessions = sorted(glob.glob(state + "/ask/sessions/*/*.jsonl"), key=os.path.getmtime)
            mains = [path for path in sessions if "MAIN TWO" in open(path).read()]
            check("main's session holds none of the thread's own words",
                  len(sessions) == 3 and len(mains) == 1 and "and Y?" not in open(mains[0]).read())
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
