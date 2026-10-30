#!/usr/bin/env python3
"""Probe long code blocks in a real reply through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-code.py .build/release/ask

Reuses the folding probe's PTY/emulator harness. No window, real credentials or host clipboard writes (Ghostty identity, OSC 52).
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


LONG = "\n".join(f"let value{n} = {n}" for n in range(1, 31))
SHORT = "\n".join(f"short {n}" for n in range(1, 6))
REPLY = f"BEFORE CODE\n```swift\n{LONG}\n```\nBETWEEN\n```sh\n{SHORT}\n```\nAFTER CODE"


def main():
    scenario(markdown=False)
    scenario(markdown=True)
    print(f"{len(checks)} checks passed")


def scenario(markdown):
    """With Markdown off the fences are drawn and an open block loses its header; with it on, the header stays and folds the block."""
    mode = "markdown" if markdown else "text"
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "fold": {"codeLines": 20}, "markdown": "on" if markdown else "off"}}, file)
        server = probe.agent.Server([probe.agent.turn([("text", REPLY)], "end_turn")])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=50)
            terminal.until(lambda: "ask>" in terminal.text())
            start = len(terminal.raw)
            # Not "Go": that is one of /continue's words. The status's check mark is the screen at rest.
            terminal.send(b"Show the code\r")
            terminal.until(lambda: b"AFTER CODE" in bytes(terminal.raw)[start:] and "\u2713 \u00b7" in terminal.text())
            terminal.repaint()
            text = terminal.text()
            check(f"{mode}: a 30-line block is one line that says its language and length", "code · swift · 30 lines" in text
                  and "let value1 = 1" not in text)
            check(f"{mode}: a 5-line block is shown as written", "short 1" in text and "short 5" in text)
            check(f"{mode}: the text around both is untouched", "BEFORE CODE" in text and "BETWEEN" in text and "AFTER CODE" in text)
            terminal.draw(lambda: terminal.click("code · swift"))
            check(f"{mode}: a click on the placeholder opens the block", "let value1 = 1" in terminal.text()
                  and "let value30 = 30" in terminal.text() and ("code · swift" in terminal.text()) == markdown)
            first, last = terminal.row("let value1 = 1") + 1, terminal.row("let value3 = 3") + 1
            copies = len(terminal.copies())
            # The end column is the last character's: Markdown indents code more than the text path does.
            end = terminal.text().split("\n")[last - 1].index("let value3 = 3") + len("let value3 = 3")
            terminal.send(f"\x1b[<0;1;{first}M\x1b[<32;{end};{last}M\x1b[<0;{end};{last}m".encode())
            terminal.until(lambda: len(terminal.copies()) > copies)
            check(f"{mode}: a selection copies the open code exactly", terminal.copies()[-1] == "let value1 = 1\nlet value2 = 2\nlet value3 = 3")
            terminal.draw(lambda: terminal.click("code · swift" if markdown else "```swift"))
            check(f"{mode}: a click on the opening fence folds it again", "code · swift · 30 lines" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x07"))
            check(f"{mode}: Ctrl+G opens every long block", "let value30 = 30" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x07"))
            check(f"{mode}: Ctrl+G folds them again", "code · swift · 30 lines" in terminal.text()
                  and "let value30 = 30" not in terminal.text())
            terminal.close()
            terminal = probe.Terminal(project, environment, resume=True, rows=50)
            terminal.until(lambda: "AFTER CODE" in terminal.text())
            terminal.repaint()
            check(f"{mode}: a resumed reply folds the same way", "code · swift · 30 lines" in terminal.text()
                  and "short 3" in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
