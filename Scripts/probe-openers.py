#!/usr/bin/env python3
"""Probe openers (roadmap 0216, ADR-0148) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-openers.py .build/release/ask

The person's own file has a command rule for files; the command is a script of the probe's own that writes its arguments to a file,
so nothing of the machine's is launched. The model's reply names a file that is there, with a line. A click on it asks first;
allowed this time it runs with the path and the line; denied it does not; allowed always it is kept in ask's state and the next
click asks nothing. The build before step 4 says the command is not run.
"""
import importlib.util
import json
import time
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def click(terminal, needle):
    # Apart from the click before it: two in the same cell within the double-click time select the word.
    time.sleep(0.8)
    terminal.repaint()
    display = terminal.screen.display
    row = next(i for i, line in enumerate(display) if needle in line)
    col = display[row].index(needle) + 3
    terminal.send(f"\x1b[<0;{col + 1};{row + 1}M\x1b[<0;{col + 1};{row + 1}m".encode())


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        root = os.path.realpath(root)
        project, config, out = root + "/project", root + "/config", root + "/out"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        target = project + "/notes.txt"
        open(target, "w").write("x\n")
        tool = root + "/tool"
        with open(tool, "w") as file:
            file.write(f"#!/bin/sh\nprintf '%s|' \"$@\" >> '{out}'\n")
        os.chmod(tool, 0o755)
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"},
                       "openers": {"rules": [{"match": {"kind": "file"}, "command": [tool, "{path}", "{line}"]}]}}, file)
        server = agent.Server([agent.turn([("text", f"See {target}:12 now.")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        grants = root + "/state/ask/openers.json"

        def ran():
            return open(out).read() if os.path.exists(out) else ""

        def ran_with(line):
            # The link's address is the standard form of the path (/var for /private/var), the same file.
            parts = ran().split("|")
            return len(parts) == 3 and os.path.realpath(parts[0]) == target and parts[1] == line

        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=120, approvals=True)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"go\r")
            terminal.until(lambda: "now." in terminal.text())
            click(terminal, "notes.txt")
            terminal.until(lambda: "Run your opener" in terminal.text() or "Not run" in terminal.text())
            text = terminal.text()
            check("a click asks before the command runs, showing it", "Run your opener for files?" in text and tool in text
                  and "Always allow this command" in text and ran() == "")
            terminal.send(b"\r")
            terminal.until(lambda: ran() != "")
            if os.environ.get("PROBE_SHOW"):
                print("ran:", repr(ran()), "grants:", os.path.exists(grants), "target:", target)
            check("allowed this time, it runs with the path and the line, and nothing is kept",
                  ran_with("12") and not os.path.exists(grants))
            os.remove(out)
            click(terminal, "notes.txt")
            terminal.until(lambda: "Run your opener" in terminal.text())
            terminal.send(b"\x1b")
            terminal.until(lambda: "Not run:" in terminal.text())
            check("denied, it does not run, and that is said", ran() == "")
            click(terminal, "notes.txt")
            terminal.until(lambda: "Run your opener" in terminal.text())
            terminal.send(b"a")
            terminal.send(b"\r")
            terminal.until(lambda: ran() != "")
            check("allowed always, it runs and is kept in ask's state, the person's alone",
                  ran_with("12") and os.path.exists(grants) and os.stat(grants).st_mode & 0o077 == 0)
            os.remove(out)
            click(terminal, "notes.txt")
            terminal.until(lambda: ran() != "")
            check("and the next click asks nothing", ran_with("12") and "Run your opener" not in terminal.text())
            terminal.close()
            terminal = None
            # Under --yes, which the probes' terminal gives by default, nothing is asked and nothing is kept.
            os.remove(out)
            os.remove(grants)
            server.responses = [agent.turn([("text", f"See {target}:7 again.")], "end_turn")]
            terminal = folding.Terminal(project, environment, columns=120)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"go\r")
            terminal.until(lambda: "again." in terminal.text())
            click(terminal, "notes.txt")
            terminal.until(lambda: ran() != "")
            check("under --yes it runs unasked, and nothing is kept",
                  ran_with("7") and "Run your opener" not in terminal.text() and not os.path.exists(grants))
        except (AssertionError, StopIteration, ValueError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
