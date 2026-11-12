#!/usr/bin/env python3
"""Probe Mermaid diagrams in the transcript (roadmap 0198) through the real binary, a PTY and a local fake provider.

Scripts/probe-mermaid.py .build/release/ask

A reply holding a closed mermaid fence is drawn as the diagram, boxes and labels, with no fence or source line left; a sequence
diagram is drawn too; the prose around them stays. Hermetic: no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []

REPLY = (
    "Here is the flow:\n\n```mermaid\nflowchart TD\n  A[Start] --> B{Ready?}\n  B -->|yes| C[Go]\n  B -->|no| D[Wait]\n```\n\n"
    "And the talk:\n\n```mermaid\nsequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi\n```\n\nDONE."
)


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        server = probe.agent.Server([probe.agent.turn([("text", REPLY)], "end_turn")])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=50)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"draw it\r")
            terminal.until(lambda: "DONE." in terminal.text())
            terminal.repaint()
            text = terminal.text()
            check("the flowchart is drawn: boxes and its labels",
                  "┌" in text and "Start" in text and "Ready?" in text and "yes" in text and "Wait" in text)
            check("the sequence diagram is drawn", "Alice" in text and "Bob" in text and "Hello" in text and "▶" in text)
            check("no fence or source line is left", "```" not in text and "flowchart" not in text and "sequenceDiagram" not in text)
            check("the prose around them stays", "Here is the flow:" in text and "And the talk:" in text)
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
