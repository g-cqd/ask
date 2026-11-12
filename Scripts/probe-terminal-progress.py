#!/usr/bin/env python3
"""A long action in the terminal's tab (notes n59 and n61) through the real binary, a scripted provider and a PTY.

Scripts/probe-terminal-progress.py .build/release/ask

The model takes seven seconds to answer. Nothing shows for the first five; then a spinner leads the tab's title and, in a terminal
that reads it (Ghostty 1.2 here), OSC 9;4 marks it busy; when the answer is in, both go. Terminal.app, which does not read OSC 9;4,
gets the spinner alone. Times are the probe's own, so its marks are wide.
"""
import importlib.util
import json
import os
import re
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent

WORKING, DONE = b"\x1b]9;4;3\x1b\\", b"\x1b]9;4;0\x1b\\"
TITLES = re.compile(rb"\x1b\]0;([^\x1b]*)\x1b\\")


def titles(raw):
    return [match.decode() for match in TITLES.findall(raw)]


def run(terminal_program, version):
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"}}, file)

        def slow(_body):
            time.sleep(7)
            return agent.turn([("text", "Slow answer.")], "end_turn")

        server = agent.Server([], route=slow)
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8", TERM_PROGRAM=terminal_program, TERM_PROGRAM_VERSION=version)
        environment.pop("TMUX", None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=110)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"take your time\r")
            sent = time.monotonic()
            while time.monotonic() - sent < 4:
                terminal.pump()
            early = bytes(terminal.raw)
            check(f"{terminal_program}: nothing in the tab for the first seconds",
                  WORKING not in early and all(title.startswith("ask") for title in titles(early)))
            terminal.until(lambda: "Slow answer." in terminal.text())
            time.sleep(0.5)
            terminal.pump()
            raw = bytes(terminal.raw)
            # The on-device model may name the conversation meanwhile, so the title is read by its lead, not its name.
            spun = [title for title in titles(raw) if not title.startswith("ask") and " ask · " in title]
            check(f"{terminal_program}: past five seconds a spinner leads the title, and steps", len(set(spun)) >= 2)
            check(f"{terminal_program}: with the answer in, the title is plain again", titles(raw)[-1].startswith("ask · "))
            return raw
        except (AssertionError, StopIteration, ValueError, IndexError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def main():
    check = folding.check
    raw = run("ghostty", "1.2.0")
    check("ghostty 1.2: OSC 9;4 marks it busy, then done", WORKING in raw and DONE in raw[raw.index(WORKING):])
    raw = run("Apple_Terminal", "455")
    check("Terminal.app: no OSC 9;4 at all", b"\x1b]9;" not in raw)


if __name__ == "__main__":
    main()
