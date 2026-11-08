#!/usr/bin/env python3
"""Probe openers (roadmap 0216, ADR-0148) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-openers.py .build/release/ask

The person's own file has an opener rule for files; the model's reply names a file that does not exist, so nothing is launched
whatever the build does. A click on it goes to the person's opener, which says so on the status line. The build before refuses
the missing file without asking the openers.
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"},'
                       ' "openers": {"rules": [{"match": {"kind": "file"}, "command": ["true", "{path}"]}]}}')
        missing = "/nonexistent-probe/notes.txt"
        server = agent.Server([agent.turn([("text", f"See {missing} now.")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=120)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"go\r")
            terminal.until(lambda: "now." in terminal.text())
            terminal.repaint()
            display = terminal.screen.display
            row = next(i for i, line in enumerate(display) if missing in line)
            col = display[row].index(missing) + 3
            terminal.send(f"\x1b[<0;{col + 1};{row + 1}M\x1b[<0;{col + 1};{row + 1}m".encode())
            terminal.until(lambda: "Not run" in terminal.text() or "Not opened" in terminal.text())
            text = terminal.text()
            if os.environ.get("PROBE_SHOW"):
                print(text)
            check("a click goes to the person's opener, which says its command is not run yet",
                  "Not run: commands as openers" in text)
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
