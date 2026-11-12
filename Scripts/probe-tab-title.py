#!/usr/bin/env python3
"""The tab's title (notes n49 and n60) through the real binary, a scripted provider and a PTY.

Scripts/probe-tab-title.py .build/release/ask

The terminal's title is saved first, the tab says `ask · project` while the conversation has no name, and the saved title is given
back on /quit. A session named in its file comes back with its name in the tab and in /resume's list. Whether Apple's on-device model
names it is not checked: what it answers is its own.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent

SAVE, RESTORE = b"\x1b[22;0t", b"\x1b[23;0t"


def title(text):
    return b"\x1b]0;" + text.encode() + b"\x1b\\"


def ended(terminal):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            terminal.pump()
        except OSError:
            return True
        pid, _ = os.waitpid(terminal.pid, os.WNOHANG)
        if pid:
            try:
                while True:
                    data = os.read(terminal.fd, 65536)
                    if not data:
                        break
                    terminal.raw.extend(data)
            except OSError:
                pass
            return True
    return False


def sessions(state):
    found = []
    for folder, _, files in os.walk(state):
        found += [os.path.join(folder, name) for name in files if name.endswith(".jsonl")]
    return found


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config, state = os.path.realpath(root) + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"}}, file)
        server = agent.Server([agent.turn([("text", "First answer.")], "end_turn")])
        environment = agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8")
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=110)
            terminal.until(lambda: "ask>" in terminal.text())
            raw = bytes(terminal.raw)
            check("the terminal's title is saved, then the tab says ask and the folder",
                  SAVE in raw and title("ask · project") in raw and raw.index(SAVE) < raw.index(title("ask · project")))
            terminal.send(b"fix the login redirect\r")
            terminal.until(lambda: "First answer." in terminal.text())
            terminal.send(b"/quit\r")
            check("on /quit the terminal's own title is given back", ended(terminal) and RESTORE in bytes(terminal.raw))
            terminal = None
            files = sessions(state)
            check("one session was kept", len(files) == 1)
            with open(files[0], "rb") as file:
                plain = file.read(1) == b"{"
            check("the session is plain JSONL, so this probe can name it", plain)
            with open(files[0]) as file:
                named = [json.loads(line).get("title") for line in file
                         if line.startswith("{") and '"conversation"' in line and '"renamed"' in line]
            # Not a check: whether the on-device model is there and what it says are the machine's.
            print("INFO named by the on-device model:", named[-1] if named else "no (unavailable, slow or no answer)")
            with open(files[0], "a") as file:
                file.write(json.dumps({"type": "thread", "event": "renamed", "id": "conversation", "title": "login redirect"}) + "\n")
            terminal = folding.Terminal(project, environment, columns=110, resume=True)
            terminal.until(lambda: "ask>" in terminal.text() and title("ask · login redirect") in bytes(terminal.raw))
            check("a named session comes back with its name in the tab", True)
            terminal.send(b"/resume ")
            terminal.until(lambda: "login redirect · fix the login redirect" in terminal.text())
            check("and in /resume's list, before its first request", True)
        except (AssertionError, StopIteration, ValueError, IndexError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
