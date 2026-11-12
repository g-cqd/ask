#!/usr/bin/env python3
"""The conversation's name, and so the tab's title, follow `threads.names` as a thread's do (note n66; the owner, 2026-11-11), through
the real binary, a PTY and a local fake provider.

Scripts/probe-conversation-model-names.py .build/release/ask

"model": the conversation's own model is asked for the name, from the first request, and the tab says the name it gives.
"numbered": no model is asked, and the tab keeps the folder. "onDevice", the default, is Apple's model: what it answers is the
machine's, so it is not checked here. Hermetic: no window, credentials or clipboard.
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


def title(text):
    return b"\x1b]0;" + text.encode() + b"\x1b\\"


def is_naming(body):
    # Anywhere in it: the Claude provider carries instructions in the first user message.
    return "Reply with a name of two to four" in json.dumps(body)


def run(names):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = os.path.realpath(root) + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": names}}, file)
        asked = []

        def route(body):
            if not is_naming(body):
                return None
            asked.append(body)
            return agent.turn([("text", "login redirect")], "end_turn")

        server = agent.Server([agent.turn([("text", "First answer.")], "end_turn")], route=route)
        environment = agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8")
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=110)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"fix the login redirect\r")
            terminal.until(lambda: "First answer." in terminal.text())
            if names == "model":
                terminal.until(lambda: title("ask · login redirect") in bytes(terminal.raw))
            else:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    terminal.pump()
            return asked, bytes(terminal.raw)
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
    asked, raw = run("model")
    check('"model": the conversation\'s model is asked, from the first request',
          len(asked) == 1 and "fix the login redirect" in json.dumps(asked[0].get("messages", "")))
    check('"model": the tab says the name it gave', title("ask · login redirect") in raw)
    asked, raw = run("numbered")
    check('"numbered": no model is asked, and the tab keeps the folder',
          not asked and title("ask · project") in raw and title("ask · login redirect") not in raw)


if __name__ == "__main__":
    main()
