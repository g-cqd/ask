#!/usr/bin/env python3
"""Check command headers (roadmap 0080) and blank thinking (roadmap 0081) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-command-header.py .build/release/ask

Requires pyte. This verifies ask's bytes through an emulator, not a physical terminal's rendering.
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


folding = load("probe_folding", "probe-folding.py")
agent = folding.agent
LONG = ": START " + "x" * 300 + " ZZEND"
MULTI = "cd .\nprintf 'MULTI_%s\\n' OK"


def tool_turn(command, timeout=None, blank_thinking=False):
    arguments = {"command": command} | ({"timeout_seconds": timeout} if timeout else {})
    events = [{"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}}]
    index = 0
    if blank_thinking:
        events += [
            {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}},
            {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "\n\n"}},
            {"type": "content_block_stop", "index": 0},
        ]
        index = 1
    events += [
        {"type": "content_block_start", "index": index, "content_block": {"type": "tool_use", "id": f"t{index}{len(command)}",
                                                                          "name": "bash", "input": {}}},
        {"type": "content_block_delta", "index": index, "delta": {"type": "input_json_delta",
                                                                  "partial_json": agent.json.dumps(arguments)}},
        {"type": "content_block_stop", "index": index},
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
            file.write('{"ui":{"prompt":"ask> ","tools":"folded","tint":"off","separator":"off","padding":"off"}}')
        server = agent.Server([tool_turn(LONG, timeout=300, blank_thinking=True), tool_turn(MULTI),
                               tool_turn("echo DEFAULT_LIMIT", timeout=120),
                               agent.turn([("text", "PROBE ANSWER")], "end_turn")])
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
            screen = terminal.screen.display
            if os.environ.get("PROBE_SHOW"):
                print(terminal.text())
            check("blank thinking leaves no block", "Thinking..." not in terminal.text())
            long_row = next(line for line in screen if "shell · timeout 5 min · : START" in line)
            check("the long command is one row, cut with … before the status", long_row.rstrip().endswith("✓")
                  and "…" in long_row and "ZZEND" not in terminal.text())
            check("nothing continues the folded command on the next row",
                  not screen[screen.index(long_row) + 1].startswith("xxxx"))
            check("a timeout equal to the default is not written (ui.timeout auto)",
                  any(line.startswith("shell · echo DEFAULT_LIMIT") for line in screen))
            check("without a timeout there is only the tool", any(line.startswith("shell · cd . …") for line in screen))
            for columns in (60, 140):
                terminal.resize(columns, 30)
                row = next(line for line in terminal.screen.display if "shell · timeout 5 min · : START" in line)
                check(f"at {columns} columns the header fills its one row", len(row.rstrip()) == columns
                      and row.rstrip().endswith("✓"))
            terminal.draw(lambda: terminal.send(b"\x0f"))  # Ctrl+O: open every tool block
            text = terminal.text()
            if os.environ.get("PROBE_SHOW"):
                print(text)
            check("open, each command is shown once", text.count(": START") == 1 and text.count("cd .") == 1)
            check("open, the command continues below its header and the output follows",
                  "ZZEND" in text and "printf 'MULTI_%s\\n' OK" in text and "MULTI_OK" in text)
            buffer, display = terminal.screen.buffer, terminal.screen.display
            header = next(i for i, line in enumerate(display) if line.startswith("shell · cd ."))
            command = next(i for i, line in enumerate(display) if line.startswith("printf 'MULTI"))
            output = next(i for i, line in enumerate(display) if line.startswith("MULTI_OK"))
            lead = len("shell · ")
            # pyte keeps SGR 2 (faint) as no attribute, so the green status colour marks the dim lead; the command is the default colour.
            check("open, the command is drawn bright: its cells use the terminal's foreground",
                  all(buffer[header][c].fg == "default" for c in range(lead, lead + 4))
                  and all(buffer[command][c].fg == "default" for c in range(6)))
            check("open, the lead keeps the status colour", buffer[header][0].fg == "green")
            raw = bytes(terminal.raw)

            def drawn_with(needle):
                at = raw.rfind(needle)
                return raw[raw.rfind(b"\x1b[", 0, at):at]

            check("open, the command row is drawn without faint, the output with it",
                  drawn_with(b"printf 'MULTI") == b"\x1b[m" and drawn_with(b"MULTI_OK") == b"\x1b[2m" and output > command)
        except (AssertionError, StopIteration):
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
