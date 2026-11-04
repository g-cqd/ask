#!/usr/bin/env python3
"""Probe threads across a resume (roadmap 0195, step 3) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-resume.py .build/release/ask

A first run merges one thread and quits while a second is still working. `ask --continue` then rebuilds the tree from the session's
records: main shows where the first started and where it merged, in place; it comes back merged and read-only, the second comes back
stopped, never restarted; `/resume` does not list the threads' own sessions; and typing in the second one's lane continues it until it
merges. Hermetic: no window, credentials or clipboard.
"""
import glob
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
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "MAIN ONE")], "end_turn"),            # 0
            turn([("text", "FIRST ANSWER")], "end_turn"),        # 1 thread-1
            turn([("text", "FIRST SUMMARY")], "end_turn"),       # 2 thread-1 merges
            turn([("tool", "c1", "sleep 30")], "tool_use"),      # 3 thread-2, still working at the quit
            turn([("text", "SECOND ANSWER")], "end_turn"),       # 4 thread-2, continued after the resume
            turn([("text", "SECOND SUMMARY")], "end_turn"),      # 5 thread-2 merges
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
            terminal.send(b"/thread first task\r")
            terminal.until(lambda: "merged · first task" in terminal.text())
            terminal.send(b"/thread second task\r")
            terminal.until(lambda: len(server.requests) > 3)
            time.sleep(0.5)
            terminal.send(b"/quit\r")
            terminal.close()
            terminal = None
            sessions = glob.glob(state + "/ask/sessions/*/*.jsonl")
            check("three sessions: main's and each thread's", len(sessions) == 3)

            terminal = probe.Terminal(project, environment, rows=40, resume=True)
            terminal.until(lambda: "MAIN ONE" in terminal.text() and "merged · first task" in terminal.text()
                           and "thread-2 · started here" in terminal.text())
            shown = terminal.text()
            check("main shows where the first thread started and where it merged, in place",
                  shown.index("MAIN ONE") < shown.index("thread-1 · started here · first task")
                  < shown.index("thread-1 · merged · first task") < shown.index("thread-2 · started here · second task"))
            runners.show(terminal)
            terminal.until(lambda: runners.row(terminal, "thread-2") is not None)
            # The list under the input leaves merged threads out; /threads lists them all.
            check("the first comes back merged, the second stopped, neither restarted",
                  runners.row(terminal, "thread-1") is None and runners.state(terminal, "thread-2") == "stopped"
                  and len(server.requests) == 4)
            terminal.send(b"/threads ")
            # The picker's rows, not the transcript's block headers: name, then state and task.
            terminal.until(lambda: "thread-1  merged · first task" in terminal.text()
                           and "thread-2  stopped · second task" in terminal.text())
            check("/threads lists the merged one", "thread-1  merged · first task" in terminal.text()
                  and "thread-2  stopped · second task" in terminal.text())
            terminal.send(b"\x15\x1b")
            runners.open_thread(terminal, "thread-1")
            check("the merged thread's lane shows its conversation", "FIRST ANSWER" in terminal.text() and "MAIN ONE" not in terminal.text())
            terminal.send(b"more?\r")
            terminal.until(lambda: "read-only" in terminal.text())
            check("and it is read-only", "has merged; it is read-only now" in terminal.text())
            terminal.send(b"\x1b")
            terminal.until(lambda: "back to the conversation" not in terminal.text())
            runners.open_lane(terminal, "thread-2")
            terminal.send(b"go on\r")
            terminal.until(lambda: len(server.requests) > 5)
            continued = json.dumps(server.requests[4]["body"])
            check("typing in the stopped one's lane continues it, from its own conversation",
                  "go on" in continued and "sleep 30" in continued and "FIRST ANSWER" not in continued)
            terminal.send(b"\x1b")
            terminal.until(lambda: "merged · second task" in terminal.text())
            check("and it merges into main like any thread", "thread-2 · merged · second task" in terminal.text())
            # A thread's own session says whose it is: its identity record.
            thread_files = [os.path.basename(p)[:-6] for p in sessions if '"event":"identity"' in open(p).read()]
            main_file = [os.path.basename(p)[:-6] for p in sessions if '"event":"identity"' not in open(p).read()]
            # Merged, it leaves the list under the input, which with nothing else to show is not drawn.
            terminal.until(lambda: runners.row(terminal, "thread-2") is None)
            terminal.send(b"/resume ")
            terminal.until(lambda: main_file[0] in terminal.text())
            picker = terminal.text()
            check("/resume lists main's session only",
                  len(thread_files) == 2 and len(main_file) == 1 and main_file[0] in picker
                  and not any(name in picker for name in thread_files))
            terminal.send(b"\x15")  # clear the draft
            terminal.send(b"\x1b")

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
