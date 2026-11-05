#!/usr/bin/env python3
"""Probe a subagent across a resume (roadmap 0063 phase 5, ADR-0146) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-subagent-resume.py .build/release/ask

ask quits while a subagent works. Resumed, it comes back stopped, its block still saying it is a subagent, its lane holding what it did;
typed in its lane, it goes on as a subagent: no agent tool of its own, and its writes refused. Hermetic.
"""
import importlib.util
import json
import os
import shutil
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
TASK = {"task": "Wait, then write", "context": "Nothing else.", "done": "Say what you did."}


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def tools(request):
    return [tool["name"] for tool in request["body"].get("tools", [])]


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-subagent-resume-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}, "agents": {"enabled": True}}, file)
    turn = probe.agent.turn
    server = probe.agent.Server([
        turn([("call", "a1", "agent", TASK)], "tool_use"),          # 0 main starts a subagent
        turn([("tool", "c1", "sleep 30")], "tool_use"),             # 1 which works
        turn([("tool", "c2", "echo ok > made.txt")], "tool_use"),   # 2 resumed and told to go on, it tries to write
        turn([("text", "COULD NOT WRITE")], "end_turn"),            # 3
        turn([("text", "SUMMARY")], "end_turn"),
    ])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
        environment.pop(key, None)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"delegate it\r")
        terminal.until(lambda: len(server.requests) >= 2 and "shell · sleep 30" not in terminal.text())
        time.sleep(1)
        terminal.send(b"/quit\r")
        terminal.close()
        terminal = probe.Terminal(project, environment, rows=40, resume=True)
        terminal.until(lambda: "thread-1" in terminal.text() and "subagent" in terminal.text())
        check("resumed, its block still says it is a subagent", "is a subagent the model started here" in terminal.text())
        runners.show(terminal)
        terminal.until(lambda: runners.row(terminal, "thread-1") is not None)
        check("and it is listed, stopped, not running", runners.state(terminal, "thread-1") == "stopped")
        runners.open_thread(terminal, "thread-1")
        terminal.until(lambda: "Wait, then write" in terminal.text())
        check("its lane holds what it did", "Wait, then write" in terminal.text())
        terminal.send(b"go on\r")
        terminal.until(lambda: len(server.requests) >= 4)
        continued = server.requests[2]
        check(f"told to go on, it is still a subagent: no agent tool ({tools(continued)})", "agent" not in tools(continued))
        check("and still read-only: its write is refused", not os.path.exists(os.path.join(project, "made.txt")))
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
