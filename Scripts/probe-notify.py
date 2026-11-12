#!/usr/bin/env python3
"""`ui.notify` (note n62) through the real binary, a scripted provider and a PTY.

Scripts/probe-notify.py .build/release/ask

With `"notification"` in Ghostty: focus reports are asked for; a turn that ends before the terminal says anything of its focus is
told with OSC 9; one that ends while the terminal says it is focused is not; once it says focus is lost, again. With the setting off,
neither focus reports nor any OSC 9 are sent.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent

FOCUS = b"\x1b[?1004h"
DONE = "ask · project: done".encode()


def notes(raw):
    return raw.count(b"\x1b]9;" + DONE + b"\x1b\\")


def run(notify):
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        ui = {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"}
        if notify:
            ui["notify"] = notify
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": ui}, file)
        server = agent.Server([agent.turn([("text", f"Answer {n}.")], "end_turn") for n in (1, 2, 3)])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8", TERM_PROGRAM="ghostty", TERM_PROGRAM_VERSION="1.2.0")
        environment.pop("TMUX", None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=110)
            terminal.until(lambda: "ask>" in terminal.text())
            counts = []
            for number, focus in [(1, b""), (2, b"\x1b[I"), (3, b"\x1b[O")]:
                if focus:
                    terminal.send(focus)
                terminal.send(f"question {number}\r".encode())
                terminal.until(lambda: f"Answer {number}." in terminal.text())
                terminal.until(lambda: "ask>" in terminal.text())
                for _ in range(10):
                    terminal.pump()
                counts.append(notes(bytes(terminal.raw)))
            return bytes(terminal.raw), counts
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
    raw, counts = run("notification")
    check("on: focus reports are asked for", FOCUS in raw)
    check("a turn ending before the terminal says anything of focus is told", counts[0] == 1)
    check("one ending while the terminal is focused is not", counts[1] == 1)
    check("once focus is lost, again", counts[2] == 2)
    raw, counts = run(None)
    check("off: no focus reports, no notification", FOCUS not in raw and b"\x1b]9;" not in raw.replace(b"\x1b]9;4;", b""))


if __name__ == "__main__":
    main()
