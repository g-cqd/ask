#!/usr/bin/env python3
"""Check keepAwake (roadmap 0090) through the real binary, a scripted provider, a PTY and the system's own list of power assertions.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-keep-awake.py .build/release/ask

While ask runs a slow shell command, `pmset -g assertions` must list ask's assertion under ask's pid; once the turn ends it must be gone;
a background job keeps it until the job ends; with "keepAwake": "off" there is none at any time. Takes real power assertions for a few
seconds; changes no setting.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check
REASON = "ask is working"


def assertions(pid):
    """The kinds of assertion pid holds under ask's reason, as pmset lists them."""
    lines = subprocess.run(["pmset", "-g", "assertions"], capture_output=True, text=True).stdout.splitlines()
    return sorted(line.split("]")[1].split()[1] for line in lines
                  if f"pid {pid}(" in line and f'"{REASON}"' in line)


def wait(condition, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.1)
    return False


def run(root, mode, arguments):
    project, config = root + "/project", root + "/config"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        # "display" is keepAwake "working" with keepDisplayAwake (roadmap 0154).
        setting = ',"keepAwake":"working","keepDisplayAwake":true' if mode == "display" else (f',"keepAwake":"{mode}"' if mode else "")
        file.write('{"ui":{"inputPrefix":"ask> "}' + setting + "}")
    server = agent.Server([agent.turn([("call", "t1", "bash", arguments)], "tool_use"),
                           agent.turn([("text", "PROBE ANSWER")], "end_turn")])
    environment = agent.environment(root + "/state", server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
    terminal = folding.Terminal(project, environment)
    try:
        terminal.until(lambda: "ask>" in terminal.text())
        held_before = assertions(terminal.pid)
        terminal.send(b"Go\r")
        held_during = wait(lambda: bool(assertions(terminal.pid)), seconds=5)
        during = assertions(terminal.pid)
        terminal.until(lambda: "PROBE ANSWER" in terminal.text())
        return terminal, server, held_before, held_during, during
    except BaseException:
        print(terminal.text(), file=sys.stderr)
        terminal.close()
        server.httpd.shutdown()
        raise


def finish(terminal, server):
    terminal.close()
    server.httpd.shutdown()
    server.httpd.server_close()


def main():
    with tempfile.TemporaryDirectory() as root:
        terminal, server, before, held, during = run(root, None, {"command": "sleep 3"})
        try:
            check("nothing is held while ask waits for a prompt", before == [])
            check("by default the Mac is kept awake while the command runs, the display may sleep",
                  held and during == ["PreventUserIdleSystemSleep"])
            check("the assertion is gone once the turn ends", wait(lambda: assertions(terminal.pid) == [], seconds=3))
        finally:
            finish(terminal, server)
    with tempfile.TemporaryDirectory() as root:
        terminal, server, _, held, during = run(root, "display", {"command": "sleep 4", "yield_seconds": 1})
        try:
            check("display mode holds the display as well", held and during == ["PreventUserIdleDisplaySleep",
                                                                                 "PreventUserIdleSystemSleep"])
            check("a job left running after the turn keeps it held", assertions(terminal.pid) != [])
            check("it is let go when the job ends", wait(lambda: assertions(terminal.pid) == [], seconds=8))
        finally:
            finish(terminal, server)
    with tempfile.TemporaryDirectory() as root:
        terminal, server, _, held, _ = run(root, "off", {"command": "sleep 2"})
        try:
            check('with "keepAwake": "off" nothing is ever held', not held and assertions(terminal.pid) == [])
        finally:
            finish(terminal, server)


if __name__ == "__main__":
    main()
