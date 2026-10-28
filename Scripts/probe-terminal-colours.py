#!/usr/bin/env python3
"""Check that the tints follow the terminal's colours (roadmap 0108) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-terminal-colours.py .build/release/ask

pyte answers no colour query, so the probe answers for the terminal, as Apple Terminal would. It posts the notification macOS sends when the
appearance changes (it changes no setting; apps that listen re-read the appearance they already have). This verifies ask's bytes through an
emulator, not a physical terminal's rendering.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
spec = importlib.util.spec_from_file_location("probe_command_header", os.path.join(HERE, "probe-command-header.py"))
headers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(headers)
agent, check = folding.agent, folding.check

QUERY = b"\x1b]10;?\x1b\\\x1b]11;?\x1b\\"
LIGHT = b"\x1b]10;rgb:0000/0000/0000\x1b\\\x1b]11;rgb:ffff/ffff/ffff\x1b\\"
DARK = b"\x1b]10;rgb:ffff/ffff/ffff\x07\x1b]11;rgb:1e1e/1e1e/1e1e\x07"


def post_appearance_change():
    subprocess.run(["osascript", "-l", "JavaScript", "-e",
                    'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter'
                    '.postNotificationNameObjectUserInfoDeliverImmediately("AppleInterfaceThemeChangedNotification", $(), $(), true); ""'],
                   check=True, capture_output=True)


def input_background(terminal):
    row = terminal.row("ask>")
    return terminal.screen.buffer[row][len("ask> ") + 2].bg


def brightness(colour):
    if len(colour) != 6:
        return None
    return sum(int(colour[i:i + 2], 16) for i in (0, 2, 4)) / 3


def faint(raw):
    """Whether any SGR in `raw` turns on faint (2), not counting the 2 that introduces a truecolour (38;2;r;g;b)."""
    for match in re.finditer(rb"\x1b\[([0-9;]*)m", raw):
        params = [int(p) if p else 0 for p in match.group(1).split(b";")]
        index = 0
        while index < len(params):
            if params[index] in (38, 48, 58):
                index += 5 if index + 1 < len(params) and params[index + 1] == 2 else 3
                continue
            if params[index] == 2:
                return True
            index += 1
    return False


def start(root, appearance=None):
    project, config = root + "/project", root + "/config"
    os.makedirs(project, exist_ok=True)
    os.makedirs(config + "/ask", exist_ok=True)
    extra = f',"appearance":"{appearance}"' if appearance else ""
    with open(config + "/ask/config.json", "w") as file:
        file.write('{"ui":{"prompt":"ask> ","tint":"on","separator":"off"' + extra + '}}')
    server = agent.Server([headers.tool_turn("echo HI"), agent.turn([("text", "PROBE ANSWER")], "end_turn")])
    environment = agent.environment(root + "/state", server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="Apple_Terminal", LANG="en_US.UTF-8")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID", "COLORFGBG"):
        environment.pop(key, None)
    terminal = folding.Terminal(project, environment)
    terminal.until(lambda: "ask>" in terminal.text())
    return terminal, server


def follows(root):
    terminal, server = start(root)
    try:
        check("at start, ask asks the terminal for its colours", QUERY in bytes(terminal.raw))
        terminal.send(b"Go\r")
        terminal.until(lambda: "PROBE ANSWER" in terminal.text())
        check("before the terminal answers, the folded tool header is faint, the only page-relative choice",
              faint(bytes(terminal.raw)))
        answered = len(terminal.raw)
        terminal.draw(lambda: terminal.send(LIGHT))
        answered = len(terminal.raw)
        terminal.repaint()
        if os.environ.get("PROBE_SHOW"):
            after = bytes(terminal.raw)[answered:]
            for match in re.finditer(rb"\x1b\[([0-9;]*)m", after):
                if faint(match.group(0)):
                    print("FAINT", after[match.start() - 30:match.end() + 30])
        check("once the terminal answers, a full repaint draws nothing faint", not faint(bytes(terminal.raw)[answered:]))
        light = brightness(input_background(terminal))
        check("a light answer gives the input a light tint", light is not None and light > 200)
        check("the answer is never typed into the input", "rgb" not in terminal.text() and "]1" not in terminal.text())
        asked = bytes(terminal.raw).count(QUERY)
        post_appearance_change()
        terminal.until(lambda: bytes(terminal.raw).count(QUERY) > asked)
        check("an appearance change makes ask ask again", True)
        terminal.draw(lambda: terminal.send(DARK))
        dark = brightness(input_background(terminal))
        check("the new dark answer gives a dark tint", dark is not None and dark < 60)
    except AssertionError:
        print(terminal.text(), file=sys.stderr)
        raise
    finally:
        terminal.close()
        server.httpd.shutdown()
        server.httpd.server_close()


def fixed(root):
    terminal, server = start(root, appearance="dark")
    try:
        check("with appearance fixed, ask asks nothing", QUERY not in bytes(terminal.raw))
        before = input_background(terminal)
        terminal.send(LIGHT)
        time.sleep(0.5)
        terminal.repaint()
        check("with appearance fixed, an answer changes nothing and is not typed",
              input_background(terminal) == before and "rgb" not in terminal.text())
        asked = bytes(terminal.raw).count(QUERY)
        post_appearance_change()
        time.sleep(1.5)
        terminal.pump()
        check("with appearance fixed, an appearance change asks nothing", bytes(terminal.raw).count(QUERY) == asked)
    except AssertionError:
        print(terminal.text(), file=sys.stderr)
        raise
    finally:
        terminal.close()
        server.httpd.shutdown()
        server.httpd.server_close()


def main():
    with tempfile.TemporaryDirectory() as root:
        follows(root + "/auto")
    with tempfile.TemporaryDirectory() as root:
        fixed(root + "/fixed")


if __name__ == "__main__":
    main()
