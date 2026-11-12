#!/usr/bin/env python3
"""Probe where a thread's approval question appears (`threads.questions`, roadmap 0195, note n19) through the real binary, a PTY and a
local fake provider, with approvals on.

Scripts/probe-thread-question-pop.py .build/release/ask

`focus`: while the person is in main, a thread's question shows there at once, named for its thread; answering it there runs the
command, the thread finishes, merges by `/merge`, and its lane asks nothing more. `after` with `questionsAfter` "3s": not at once, then once it
has waited. PROBE_QUESTIONS overrides the mode both runs set (`lane` shows the probe failing as it did before the setting).
Hermetic: no window, credentials or clipboard.
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


def asks_in_main(terminal):
    return "thread-1: " in terminal.text() and "Allow it?" in terminal.text() and "back to the conversation" not in terminal.text()


def run(mode, after=None):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        threads = {"names": "numbered", "questions": os.environ.get("PROBE_QUESTIONS", mode)}
        if after:
            threads["questionsAfter"] = after
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": threads}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "MAIN ONE")], "end_turn"),
            turn([("tool", "c1", "touch thread.txt")], "tool_use"),
            turn([("text", "THREAD DONE")], "end_turn"),
            turn([("text", "THREAD SUMMARY")], "end_turn"),
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
            terminal.until(lambda: "started here" in terminal.text())
            if after:
                terminal.until(lambda: len(server.requests) >= 2)
                time.sleep(1)
                terminal.repaint()
                check(f"{mode}: not at once", not asks_in_main(terminal) and not os.path.exists(made))
            # The whole section, not its first row: a frame read part way through shows the rows it has not reached yet as they were.
            terminal.until(lambda: asks_in_main(terminal) and "touch thread.txt" in terminal.text())
            check(f"{mode}: main shows the thread's question, named for it",
                  asks_in_main(terminal) and "touch thread.txt" in terminal.text())
            if after:
                return
            terminal.send(b"\r")
            terminal.until(lambda: os.path.exists(made))
            runners.merge(terminal, "thread-1")
            terminal.until(lambda: "merged · make a file" in terminal.text())
            check(f"{mode}: answered in main, the command runs and the thread finishes and merges", os.path.exists(made))
            runners.open_thread(terminal, "thread-1")
            terminal.until(lambda: "THREAD DONE" in terminal.text())
            check(f"{mode}: its lane asks nothing more", "Allow it?" not in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def main():
    run("focus")
    run("after", after="3s")
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
