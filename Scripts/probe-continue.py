#!/usr/bin/env python3
"""Check "continue" through the real binary, a scripted provider and a PTY (roadmaps 0097 and 0112).

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-continue.py .build/release/ask

The bare word `continue`, then Right pressed twice on an empty input, must each reach the provider as the same one message; a sentence that
starts with the word must reach it unchanged. pyte, not a physical terminal.
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
agent, check = folding.agent, folding.check
SENT = "Continue the work where you stopped."


def last_user_text(server):
    for message in reversed(server.requests[-1]["body"]["messages"]):
        if message["role"] == "user":
            return [b["text"] for b in message["content"] if b.get("type") == "text"][-1]


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","separator":"off"}}')
        server = agent.Server([agent.turn([("text", f"ANSWER {n}")], "end_turn") for n in range(1, 4)])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"continue with the tests\r")
            terminal.until(lambda: "ANSWER 1" in terminal.text())
            check("a sentence that starts with the word is sent unchanged", last_user_text(server) == "continue with the tests")
            terminal.send(b"continue\r")
            terminal.until(lambda: "ANSWER 2" in terminal.text())
            check("the bare word sends the fixed message", last_user_text(server) == SENT)
            terminal.send(b"\x1b[C")
            time.sleep(0.15)
            terminal.send(b"\x1b[C")
            terminal.until(lambda: "ANSWER 3" in terminal.text())
            check("Right twice on an empty input sends the same message", len(server.requests) == 3 and last_user_text(server) == SENT)
        except (AssertionError, TypeError):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
