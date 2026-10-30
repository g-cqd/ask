#!/usr/bin/env python3
"""The status mark says whether the sandbox is on, and a click names it (roadmap 0133) through the real binary and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-sandbox-mark.py .build/release/ask

Sandboxed: a green check; a click shows a green `Sandboxed`, and five seconds later the check is back. With `--no-sandbox`: a `!` in the
warning colour; a click shows `Not sandboxed`. A click away from the mark does nothing. pyte, not a physical terminal.
"""
import importlib.util
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check
ROWS = 30


def run(label, word, mark, colour, yellow_names):
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/p", root + "/c"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        open(config + "/ask/config.json", "w").write('{"ui":{"inputPrefix":"ask> ","separator":"off"}}')
        server = agent.Server([])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment, columns=100, rows=ROWS)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.repaint()
            status = lambda: terminal.screen.display[ROWS - 1]
            cell = lambda: terminal.screen.buffer[ROWS - 1][0]
            check(f"{label}: the idle mark is {mark!r} in {colour}", status().startswith(mark + " · ") and cell().fg in yellow_names)
            terminal.send(f"\x1b[<0;20;{ROWS}M\x1b[<0;20;{ROWS}m".encode())  # a click on the label, not the mark
            time.sleep(0.4)
            terminal.pump()
            check(f"{label}: a click away from the mark does nothing", status().startswith(mark + " · "))
            terminal.draw(lambda: terminal.send(f"\x1b[<0;1;{ROWS}M\x1b[<0;1;{ROWS}m".encode()))
            check(f"{label}: a click on the mark shows `{word}`", status().startswith(word + " · ") and cell().fg in yellow_names)
            time.sleep(5.6)
            terminal.pump()
            terminal.repaint()
            check(f"{label}: five seconds later the mark is back", status().startswith(mark + " · "))
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()


def main():
    run("sandboxed", "Sandboxed", "✓", "green", ("green",))
    folding_binary = folding.BINARY
    # --no-sandbox is a launch flag: run a wrapper script that adds it.
    wrapper = tempfile.mkdtemp() + "/ask"
    open(wrapper, "w").write(f'#!/bin/sh\nexec "{folding_binary}" --no-sandbox "$@"\n')
    os.chmod(wrapper, 0o755)
    folding.BINARY = wrapper
    try:
        run("unsandboxed", "Not sandboxed", "!", "yellow", ("brown", "yellow"))
    finally:
        folding.BINARY = folding_binary


if __name__ == "__main__":
    main()
