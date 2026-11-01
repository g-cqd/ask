#!/usr/bin/env python3
"""Probe `/idea`, `/ideas` and the `ideas` tool through the real binary, a PTY and a local fake provider (roadmap 0180).

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-ideas.py .build/release/ask

An idea is saved and said so; `/ideas` lists it, and choosing it puts it in the input to edit with the list closed; Enter keeps the
edit and opens the list again with the new words; the model is sent no idea unasked, and reads the edited one through its tool.
Hermetic: no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def results(request):
    return [block.get("content") for message in request["body"]["messages"]
            for block in (message["content"] if isinstance(message["content"], list) else []) if block.get("type") == "tool_result"]


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("text", "Started.")], "end_turn"),
            turn([("call", "c1", "ideas", {"read": {}})], "tool_use"),
            turn([("text", "Read them.")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"begin\r")
            terminal.until(lambda: "Started." in terminal.text() and "ask>" in terminal.text())
            terminal.send(b"/idea fold the sidebar\r")
            terminal.until(lambda: "Saved idea i1." in terminal.text())
            check("an idea is saved, and said so", "Saved idea i1." in terminal.text())
            terminal.draw(lambda: terminal.send(b"/ideas "))
            terminal.until(lambda: "fold the sidebar" in terminal.text() and "[new]" in terminal.text())
            check("/ideas lists it, new", "i1" in terminal.text())
            terminal.draw(lambda: terminal.send(b"i1"))
            terminal.draw(lambda: terminal.send(b"\r"))
            terminal.until(lambda: "ask> /ideas i1 fold the sidebar" in terminal.text())
            check("choosing it puts it in the input to edit", "ask> /ideas i1 fold the sidebar" in terminal.text())
            check("with the list closed", "ideas 1 of" not in terminal.text() and "[new]" not in terminal.text().split("ask> /ideas i1")[-1])
            terminal.draw(lambda: terminal.send(b" when narrow"))
            terminal.send(b"\r")
            terminal.until(lambda: "Edited i1." in terminal.text())
            # The list is drawn after the notice, maybe over more than one write: wait for its whole row and the input under it, not
            # for the edited line the transcript already shows.
            def reopened():
                after = terminal.text().split("Edited i1.")[-1]
                row = after.split("[new]")[-1].split("\n")[0].strip() if "[new]" in after else ""
                return row.endswith("fold the sidebar when narrow") and "ask> /ideas" in after

            terminal.until(reopened)
            check("Enter keeps the edit and opens the list again, with the new words", reopened())
            terminal.send(b"\x1b")
            time.sleep(0.2)
            terminal.send(b"\x15")  # Ctrl+U: an empty input
            time.sleep(0.2)
            terminal.send(b"what did I note?\r")
            terminal.until(lambda: "Read them." in terminal.text())
            check("no idea was sent unasked", "fold the sidebar" not in json.dumps(server.requests[0]["body"])
                  and "fold the sidebar" not in json.dumps(server.requests[1]["body"]))
            seen = json.dumps(results(server.requests[2])) if len(server.requests) > 2 else ""
            check("the model reads the edited idea through its tool", "1 new" in seen and "fold the sidebar when narrow" in seen)
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.send(b"/quit\r")
                time.sleep(0.2)
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
