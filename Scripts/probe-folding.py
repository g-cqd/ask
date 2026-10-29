#!/usr/bin/env python3
"""Exercise thinking/tool folding through the real binary, a local scripted provider, and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-folding.py .build/release/ask

Requires pyte. No windows or credentials; Ghostty identity routes copies to captured OSC 52 rather than pbcopy.
This verifies ask's bytes through an emulator, not a physical terminal's rendering or clipboard.
"""
import base64
import fcntl
import importlib.util
import os
import pty
import re
import select
import signal
import struct
import sys
import tempfile
import termios
import time

sys.path.insert(0, os.environ.get("ASK_PYTE", "/tmp/ask-pty/lib"))
import pyte

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_screen

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def thinking_turn():
    events = [
        {"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}},
        {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "FIRST THOUGHT\nSECOND THOUGHT"}},
        {"type": "content_block_stop", "index": 0},
        {"type": "content_block_start", "index": 1, "content_block": {"type": "tool_use", "id": "t1", "name": "read", "input": {}}},
        {"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": '{"path":"note.txt"}'}},
        {"type": "content_block_stop", "index": 1},
        {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 3}},
        {"type": "message_stop"},
    ]
    return agent.sse(events)


class Terminal:
    def __init__(self, project, environment, resume=False, columns=100, rows=30):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
            os.chdir(project)
            os.execve(BINARY, [BINARY] + (["--continue"] if resume else []), environment)
        self.screen, self.stream = probe_screen.make(columns, rows)
        self.raw = bytearray()

    def pump(self):
        if select.select([self.fd], [], [], 0.05)[0]:
            data = os.read(self.fd, 65536)
            self.raw.extend(data)
            self.stream.feed(data)

    def until(self, condition):
        deadline = time.monotonic() + 15
        while not condition():
            if time.monotonic() > deadline:
                raise AssertionError("screen condition timed out:\n" + self.text())
            self.pump()

    def repaint(self):
        # SIGWINCH forces a position-addressed full frame even when the size stays the same. pyte lacks regional scrolling.
        start = len(self.raw)
        os.kill(self.pid, signal.SIGWINCH)
        self.until(lambda: b"\x1b[1;1H" in bytes(self.raw)[start:]
                   and bytes(self.raw)[start:].endswith(b"\x1b[?2026l"))

    def resize(self, columns, rows):
        self.screen.resize(rows, columns)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        self.repaint()

    def draw(self, action):
        frames = bytes(self.raw).count(b"\x1b[?2026l")
        action()
        self.until(lambda: bytes(self.raw).count(b"\x1b[?2026l") > frames)
        self.repaint()

    def text(self):
        return "\n".join(self.screen.display)

    def send(self, value):
        os.write(self.fd, value)

    def row(self, prefix):
        return next(index for index, line in enumerate(self.screen.display) if prefix in line)

    def click(self, prefix):
        row = self.row(prefix) + 1
        self.send(f"\x1b[<0;4;{row}M\x1b[<0;4;{row}m".encode())

    def copies(self):
        return [base64.b64decode(value).decode() for value in re.findall(
            rb"\x1b\]52;c;([A-Za-z0-9+/=]+)(?:\x07|\x1b\\)", bytes(self.raw))]

    def close(self):
        # Only this disposable child, after its read tool has finished. Never block behind terminal restoration on a full PTY.
        os.close(self.fd)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(self.pid, 0)


def check(label, condition):
    if not condition:
        raise AssertionError(label)
    print("PASS " + label, flush=True)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(project + "/note.txt", "w") as file:
            file.write("ALPHA OUTPUT\nBETA OUTPUT\n")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"prompt":"ask> ","thinking":"folded","tools":"folded","tint":"off","separator":"off"}}')
        server = agent.Server([thinking_turn(), agent.turn([("text", "PROBE ANSWER")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = Terminal(project, environment)
            terminal.until(lambda: "ask>" in terminal.text())
            beginning = len(terminal.raw)
            terminal.send(b"Go\r")
            terminal.until(lambda: b"PROBE ANSWER" in bytes(terminal.raw)[beginning:]
                           )
            terminal.repaint()
            check("thinking and tool output start folded", "Thinking..." in terminal.text()
                  and "read · note.txt" in terminal.text() and "2 lines · ✓" in terminal.text()
                  and "FIRST THOUGHT" not in terminal.text() and "ALPHA OUTPUT" not in terminal.text())
            check("the status retains the terminal background", all(
                not terminal.screen.buffer[29][col].reverse and terminal.screen.buffer[29][col].bg == "default"
                for col in range(100)))
            terminal.draw(lambda: terminal.click("Thinking..."))
            check("the expanded reasoning is visible", "SECOND THOUGHT" in terminal.text())
            check("a click opens thinking only", "FIRST THOUGHT" in terminal.text() and "ALPHA OUTPUT" not in terminal.text())
            # The shortcut flips the kind's default, discarding per-block overrides: first all open, then all folded.
            terminal.draw(lambda: terminal.send(b"\x14"))  # Ctrl+T: open every thinking block
            terminal.draw(lambda: terminal.send(b"\x14"))  # Ctrl+T: fold every thinking block
            terminal.draw(lambda: terminal.send(b"\x0f"))  # Ctrl+O
            check("Ctrl+T and Ctrl+O control separate kinds", "FIRST THOUGHT" not in terminal.text()
                  and "BETA OUTPUT" in terminal.text())
            first, last = terminal.row("ALPHA OUTPUT") + 1, terminal.row("BETA OUTPUT") + 1
            terminal.send(f"\x1b[<0;1;{first}M\x1b[<32;13;{last}M\x1b[<0;13;{last}m".encode())
            terminal.until(lambda: bool(terminal.copies()))
            check("a selection copies the expanded output without indentation", terminal.copies()[-1] == "ALPHA OUTPUT\nBETA OUTPUT")
            terminal.draw(lambda: terminal.send(b"\x0f"))
            check("closing output clears its highlight", not any(
                cell.reverse for row in range(28) for cell in terminal.screen.buffer[row].values()))
            terminal.close()
            terminal = Terminal(project, environment, resume=True)
            terminal.until(lambda: "PROBE ANSWER" in terminal.text())
            terminal.repaint()
            check("resume replays thinking and tool output folded", "Thinking..." in terminal.text()
                  and "read · note.txt" in terminal.text() and "2 lines · ✓" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x14"))
            check("resumed reasoning can be opened", "FIRST THOUGHT" in terminal.text())
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
