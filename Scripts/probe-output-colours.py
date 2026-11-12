#!/usr/bin/env python3
"""Check a command's own colours and links in its block (note n30) through the real binary, a scripted provider and a PTY.

Scripts/probe-output-colours.py .build/release/ask

The command prints a red bold word, an OSC 8 link, a title change (OSC 0) and a line clear. The block shows the text without any of
the escapes as text, the word in red and bold, and the link as ask's own OSC 8; the title change and the clear never reach the
terminal. The build before shows `[1;31m` in the block. Requires pyte: ask's bytes through an emulator, not a physical terminal.
"""
import importlib.util
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent
COMMAND = ("printf '\\033[1;31mERRWORD\\033[0m plain \\033]8;;https://example.com/n30\\033\\\\LINKED\\033]8;;\\033\\\\ "
           "\\033]0;PWN%sTITLE\\007\\033[2Kend\\n' ''")


def tool_turn(command):
    events = [
        {"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        {"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "t1", "name": "bash", "input": {}}},
        {"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta",
                                                              "partial_json": agent.json.dumps({"command": command})}},
        {"type": "content_block_stop", "index": 0},
        {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 3}},
        {"type": "message_stop"},
    ]
    return agent.sse(events)


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","fold":{"tools":false},"tint":"off","separator":"off","padding":"off"}}')
        server = agent.Server([tool_turn(COMMAND), agent.turn([("text", "PROBE ANSWER")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment)
            terminal.until(lambda: "ask>" in terminal.text())
            beginning = len(terminal.raw)
            terminal.send(b"Go\r")
            terminal.until(lambda: b"PROBE ANSWER" in bytes(terminal.raw)[beginning:])
            terminal.repaint()
            text = terminal.text()
            if os.environ.get("PROBE_SHOW"):
                print(text)
            raw = bytes(terminal.raw)[beginning:]
            display = terminal.screen.display
            # The header shows the command as written, over two rows; the output is the first row after it with no escape written out.
            header = next(i for i, line in enumerate(display) if line.startswith("shell · printf"))
            output = [line for line in display[header + 1:] if line.strip() and "\\033" not in line][0]
            check("the output reads as plain text", output.strip() == "ERRWORD plain LINKED end")
            check("no escape shows as text, and the title is not written", "PWNTITLE" not in text)
            row = display.index(output)
            col = display[row].index("ERRWORD")
            cells = [terminal.screen.buffer[row][c] for c in range(col, col + 7)]
            check("the word is drawn red and bold", all(c.fg == "red" and c.bold for c in cells))
            after = terminal.screen.buffer[row][display[row].index("plain")]
            check("and the text after the reset is not", after.fg != "red" and not after.bold)
            check("the link is written as ask's own OSC 8, over its text",
                  re.search(rb"\x1b\]8;[^;\x1b\x07]*;https://example\.com/n30(\x1b\\|\x07)(\x1b\[[0-9;:]*m)*LINKED", raw) is not None)
            check("the title change never reaches the terminal", b"PWNTITLE" not in raw)
        except (AssertionError, StopIteration, ValueError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
