#!/usr/bin/env python3
"""Probe `/thread` (roadmaps 0194, 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread.py .build/release/ask

After one prompt, `/thread` forks the conversation and runs it beside main, marked where it started. In its lane, `/thread` starts a
thread under it. The outer thread finishes first and is held: it waits for the inner one. The inner one merges into it with a summary;
then the outer one merges into main, its summary carrying the inner one's. Main's next message takes that summary to the model, a merged
thread is read-only, and main's session holds none of the threads' words. Hermetic: no window, credentials or clipboard.
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


def wait(terminal, condition, seconds):
    """`terminal.until`, with a deadline of its own: the threads here sleep for seconds on purpose."""
    deadline = time.monotonic() + seconds
    while not condition():
        if time.monotonic() > deadline:
            raise AssertionError("screen condition timed out:\n" + terminal.text())
        terminal.pump()


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
            turn([("text", "MAIN ONE")], "end_turn"),                      # 0 main
            turn([("tool", "c1", "sleep 4")], "tool_use"),                 # 1 thread-1 starts, and sleeps
            turn([("tool", "c2", "sleep 9")], "tool_use"),                 # 2 thread-2 starts under it, and sleeps longer
            turn([("text", "OUTER ANSWER")], "end_turn"),                  # 3 thread-1 ends first: held
            turn([("text", "INNER ANSWER")], "end_turn"),                  # 4 thread-2 ends
            turn([("text", "INNER SUMMARY")], "end_turn"),                 # 5 thread-2's summary, into thread-1
            turn([("text", "OUTER SUMMARY")], "end_turn"),                 # 6 thread-1's summary, into main
            turn([("text", "MAIN TWO")], "end_turn"),                      # 7 main
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
            terminal.send(b"/thread look into X\r")
            terminal.until(lambda: "started here" in terminal.text() and len(server.requests) > 1)
            check("the thread is marked where it started, and its request carries main's conversation and its task",
                  "thread-1 · started here · look into X" in terminal.text()
                  and "MAIN ONE" in body(server, 1) and "look into X" in body(server, 1))
            terminal.send(b"/jobs\r")
            terminal.until(lambda: "thread-1  look into X" in terminal.text())
            terminal.send(b"\x1b[B")
            time.sleep(0.3)
            terminal.send(b"\r")
            terminal.until(lambda: "main  back to the conversation" in terminal.text())
            terminal.send(b"/thread go deeper\r")
            terminal.until(lambda: len(server.requests) > 2)
            check("/thread in its lane forks that thread, its request carrying the outer thread's work",
                  "look into X" in body(server, 2) and "sleep 4" in body(server, 2) and "go deeper" in body(server, 2))
            wait(terminal, lambda: "waiting on its threads" in terminal.text(), 20)
            check("the outer thread, done first, is held: it waits for the inner one",
                  "thread-1  look into X · waiting on its threads" in terminal.text() and len(server.requests) == 4)
            wait(terminal, lambda: "merged · look into X" in terminal.text() or len(server.requests) > 6, 30)
            time.sleep(0.5)
            inner, outer = body(server, 5), body(server, 6)
            check("the inner thread merges first, with a summary request over its own work",
                  "merging back into the conversation it was forked from" in inner and "INNER ANSWER" in inner)
            check("then the outer one, its summary request carrying the inner one's summary",
                  "merging back" in outer and "INNER SUMMARY" in outer and "OUTER ANSWER" in outer)
            terminal.send(b"and more?\r")
            terminal.until(lambda: "read-only" in terminal.text())
            check("a merged thread is read-only", "has merged; it is read-only now" in terminal.text() and len(server.requests) == 7)
            terminal.send(b"\x1b")
            terminal.until(lambda: "back to the conversation" not in terminal.text())
            terminal.until(lambda: "merged · look into X" in terminal.text())
            check("main shows the merge as a folded block", "thread-1 · merged · look into X" in terminal.text()
                  and "OUTER SUMMARY" not in terminal.text())
            terminal.send(b"next\r")
            terminal.until(lambda: "MAIN TWO" in terminal.text())
            sent = body(server, 7)
            check("main's next message takes the outer thread's summary to the model, the inner one inside it",
                  "--- thread thread-1 ---" in sent and "OUTER SUMMARY" in sent and "--- thread thread-2 ---" not in sent)
            sessions = sorted(glob.glob(state + "/ask/sessions/*/*.jsonl"), key=os.path.getmtime)
            mains = [path for path in sessions if "MAIN TWO" in open(path).read()]
            check("main's session holds none of the threads' own words",
                  len(sessions) == 3 and len(mains) == 1 and "go deeper" not in open(mains[0]).read()
                  and "INNER ANSWER" not in open(mains[0]).read())
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
