#!/usr/bin/env python3
"""Probe that stopping stops a subagent and leaves nothing running (roadmap 0063, phase 2; ADR-0146) through the real binary, a PTY
and a local fake provider, with real processes.

Scripts/probe-subagent-stop.py .build/release/ask

Main's model starts a subagent whose command is a long `sleep` marked so it can be found; Ctrl+C stops main's turn, and with it the
subagent: within a few seconds no process with the mark is left, and the subagent merges on its own. Hermetic.
"""
import importlib.util
import json
import re
import os
import shutil
import subprocess
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
# The duration is the mark: a shell runs a last simple command in its own place, so a comment would not survive to the process.
MARK = f"sleep 299.{os.getpid()}"
TASK = {"task": "Wait a long while", "context": "Nothing else.", "done": "Say when the wait ends."}


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def running():
    # The whole command line, anchored: a shell whose script merely mentions the mark is not it.
    found = subprocess.run(["pgrep", "-f", "^" + re.escape(MARK) + "$"], capture_output=True, text=True).stdout.split()
    return [pid for pid in found if int(pid) != os.getpid()]


def gone(seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if not running():
            return True
        time.sleep(0.2)
    return not running()


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-subagent-stop-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}, "agents": {"enabled": True}}, file)
    turn = probe.agent.turn
    server = probe.agent.Server([
        turn([("call", "a1", "agent", TASK)], "tool_use"),                       # 0 main asks for a subagent
        turn([("tool", "c1", MARK)], "tool_use"),               # 1 which runs a long command
        turn([("text", "STOPPED SUMMARY")], "end_turn"),                          # 2 its summary, if one is asked
        turn([("text", "MAIN AFTER")], "end_turn"),
    ])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
        environment.pop(key, None)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"delegate a long wait\r")
        terminal.until(lambda: bool(running()))
        check("the subagent's command runs", bool(running()))
        terminal.send(b"\x03")
        check("Ctrl+C on main's turn stops the subagent, and no process of its is left", gone())
        # Stopped, it merges on its own (subagents never ask): its block says so, and the list, which leaves merged threads out,
        # does not show it running.
        terminal.until(lambda: "thread-1 · merged · Wait a long while" in terminal.text())
        check("and it merges on its own, not left running", runners.state(terminal, "thread-1") in (None, "merged"))
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        for pid in running():
            subprocess.run(["kill", "-9", pid])
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
