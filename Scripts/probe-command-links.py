#!/usr/bin/env python3
"""Note n11 through the real binary, a scripted provider and a PTY: in a reply, only ask's own commands are drawn as commands, and a
click on one fills an empty input; another single `/word` is text, and a path is still a hyperlink.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-command-links.py .build/release/ask

Requires pyte. This reads ask's bytes through an emulator, not a physical terminal's look.
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

checks = []
REPLY = "Type /reload to apply it, not /frobnicate; the log is in /tmp/probe-log.txt."


def check(label, condition):
    if not condition:
        raise AssertionError(label)
    checks.append(label)
    print("PASS " + label, flush=True)


def find(terminal, needle):
    for row, line in enumerate(terminal.screen.display):
        if needle in line:
            return row, line.index(needle)
    raise AssertionError(f"not drawn: {needle}")


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-command-links-")
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off"}}, file)
    server = probe.agent.Server([probe.agent.turn([("text", REPLY)], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=30)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Go\r")
        terminal.until(lambda: "/frobnicate" in terminal.text())
        terminal.repaint()
        raw = bytes(terminal.raw)
        check("a path is still sent as a hyperlink", b"file:///tmp/probe-log.txt" in raw)
        check("an unknown /word is not a link", b"file:///frobnicate" not in raw)
        check("a command is not sent to the terminal as a link", b"file:///reload" not in raw and b"ask-command" not in raw)
        row, col = find(terminal, "/reload")
        # Read from the bytes: ask sends the underline as `4:1`, which pyte does not take.
        check("the command is underlined, the unknown word is not",
              b"\x1b[4:1m/reload" in raw and b"m/frobnicate" not in raw)
        terminal.draw(lambda: terminal.send(f"\x1b[<0;{col + 3};{row + 1}M\x1b[<0;{col + 3};{row + 1}m".encode()))
        check("a click on it fills the empty input", any(text.startswith("ask> /reload") for text in terminal.screen.display))
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
