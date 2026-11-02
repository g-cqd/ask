#!/usr/bin/env python3
"""Probe `/idea` typed before the first prompt (the owner's choice, 2026-11-02, roadmap 0180) through the real binary, a PTY and a
local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-ideas-early.py .build/release/ask

Before any session, `/idea` says the idea is kept for the session; the first prompt starts the session and saves it, saying so; `/ideas`
lists it. Hermetic: no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        server = probe.agent.Server([probe.agent.turn([("text", "Started.")], "end_turn")])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/idea an early bird\r")
            terminal.until(lambda: "Kept:" in terminal.text())
            check("before the first prompt, the idea is kept for the session, and said so",
                  "saved to your ideas when the session starts" in terminal.text())
            terminal.send(b"begin\r")
            terminal.until(lambda: "Started." in terminal.text())
            terminal.until(lambda: "before the session started: i1." in terminal.text())
            check("the first prompt saves it, and says which it is", "before the session started: i1." in terminal.text())
            terminal.draw(lambda: terminal.send(b"/ideas\r"))
            terminal.until(lambda: "an early bird" in terminal.text().split("Started.")[-1])
            check("/ideas lists it", "an early bird" in terminal.text().split("Started.")[-1])
        finally:
            if terminal is not None:
                terminal.close()
            server.httpd.shutdown()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
