#!/usr/bin/env python3
"""Probe where a resume shows a thread merged while its parent was working (roadmap 0195, the audit of 2026-11-06), through the real
binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-merge-midturn.py .build/release/ask

Main runs a slow command; meanwhile the person merges a thread by `/merge` in its lane. The merge is recorded at main's leaf then, but its
summary goes with the next prompt, not with the command's result. So once resumed, the merge block comes after the reply main gave at the
end of that turn, not before it, and before the next prompt. The build before fails the order check. Hermetic: no window, credentials or clipboard.
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
            turn([("text", "MAIN ONE")], "end_turn"),            # 0
            turn([("text", "SIDE ANSWER")], "end_turn"),         # 1 thread-1
            turn([("tool", "c1", "sleep 4")], "tool_use"),       # 2 main, working
            turn([("text", "SIDE SUMMARY")], "end_turn"),        # 3 thread-1 merges, by /merge, while main works
            turn([("text", "MAIN AFTER")], "end_turn"),          # 4 main, once its command ends
            turn([("text", "MAIN NEXT")], "end_turn"),           # 5 main, the next prompt, with the summary
        ])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=50)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"hello\r")
            terminal.until(lambda: "MAIN ONE" in terminal.text())
            terminal.send(b"/thread side task\r")
            terminal.until(lambda: "thread-1 · started here" in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.state(terminal, "thread-1") == "idle")
            terminal.send(b"work\r")
            terminal.until(lambda: len(server.requests) > 2)
            runners.open_thread(terminal, "thread-1")
            terminal.send(b"/merge\r")
            terminal.until(lambda: len(server.requests) > 3)
            check("the merge's summary is asked for while main's command still runs", len(server.requests) == 4)
            terminal.send(b"\x1b")
            terminal.until(lambda: "MAIN AFTER" in terminal.text())
            terminal.until(lambda: "merged · side task" in terminal.text())
            check("the summary is not sent with the command's result", "SIDE SUMMARY" not in json.dumps(server.requests[4]["body"]))
            terminal.send(b"next prompt\r")
            terminal.until(lambda: "MAIN NEXT" in terminal.text())
            check("but with the next prompt", "SIDE SUMMARY" in json.dumps(server.requests[5]["body"]))
            terminal.send(b"/quit\r")
            terminal.close()
            terminal = None

            terminal = probe.Terminal(project, environment, rows=50, resume=True)
            terminal.until(lambda: "MAIN NEXT" in terminal.text() and "merged · side task" in terminal.text())
            shown = terminal.text()
            check("resumed, the merge is shown after the reply that ended the turn it came in, before the next prompt",
                  shown.index("thread-1 · started here") < shown.index("MAIN AFTER")
                  < shown.index("thread-1 · merged · side task") < shown.index("next prompt"))
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
