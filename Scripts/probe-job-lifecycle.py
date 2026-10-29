#!/usr/bin/env python3
"""Real yielded job: original-block streaming, focus independence, unread wait output, hex IDs and completion.

Run with a Python environment providing pyte. Force full repaint after transcript
changes because pyte does not implement regional scrolling. No real credentials.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import select
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def click(terminal, row, column=2):
    terminal.draw(lambda: terminal.send(
        f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode()))


def shown(terminal, line):
    """Whether `line` is a row of its own: the command in the block's header also says STREAM_TWO, so a substring proves nothing."""
    return any(text.strip() == line for text in terminal.screen.display)


def eventually(terminal, line, seconds=2.0):
    """Whether `line` becomes a row of its own within `seconds`, repainting: a lane's output reaches the main block within about 0.3 s."""
    deadline = time.monotonic() + seconds
    while True:
        terminal.repaint()
        if shown(terminal, line):
            return True
        if time.monotonic() > deadline:
            return False
        time.sleep(0.1)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = Path(root) / "project", Path(root) / "config"
        project.mkdir()
        (config / "ask").mkdir(parents=True)
        (config / "ask/config.json").write_text(json.dumps({"ui": {
            "prompt": "ask> ", "separator": "off", "tint": "off", "localizedDurations": "off"}}))
        command = ("printf 'STREAM_ONE\\n'; while [ ! -f second ]; do sleep .05; done; "
                   "printf 'STREAM_TWO\\n'; while [ ! -f finish ]; do sleep .05; done; exit 7")
        turn = probe.agent.turn
        server = probe.agent.Server([
            turn([("call", "t1", "bash", {"command": command, "yield_seconds": 1})], "tool_use"),
            turn([("text", "JOB RUNNING")], "end_turn"),
            turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_output": "STREAM_TWO", "timeout_seconds": 3})],
                 "tool_use"),
            turn([("text", "WAIT PRESERVED")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=str(config))
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        terminal = None
        try:
            terminal = probe.Terminal(str(project), environment, columns=140, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Start\r")
            terminal.until(lambda: b"JOB RUNNING" in terminal.raw and "shell \u00b7 [#" in terminal.text())
            terminal.repaint()
            label = re.search(r"shell · \[(#[0-9a-f]{4})\]", terminal.text()).group(1)
            row = next(i for i, text in enumerate(terminal.screen.display) if "shell · [" in text)
            click(terminal, row)
            probe.check("original tool unfolds with the job's initial output", shown(terminal, "STREAM_ONE"))
            terminal.draw(lambda: terminal.send(b"/tasks\r"))
            job_row = next(i for i, text in enumerate(terminal.screen.display) if text.startswith("[" + label + "]  "))
            click(terminal, job_row)
            terminal.until(lambda: "STREAM_ONE" in terminal.text() and "main › [" + label + "]" in terminal.text())
            (project / "second").touch()
            terminal.until(lambda: shown(terminal, "STREAM_TWO"))
            probe.check("focused output keeps streaming", shown(terminal, "STREAM_ONE") and shown(terminal, "STREAM_TWO"))
            terminal.draw(lambda: terminal.send(b"\x1b"))
            probe.check("main block was updated while another lane was focused", eventually(terminal, "STREAM_TWO")
                        and "JOB RUNNING" in terminal.text())
            row = next(i for i, text in enumerate(terminal.screen.display) if "shell · [" in text)
            click(terminal, row)
            probe.check("a streamed block still folds", not shown(terminal, "STREAM_TWO"))
            row = next(i for i, text in enumerate(terminal.screen.display) if "shell · [" in text)
            click(terminal, row)
            probe.check("a streamed block still unfolds", shown(terminal, "STREAM_TWO"))
            terminal.send(b"Wait\r")
            terminal.until(lambda: b"WAIT PRESERVED" in terminal.raw)
            result = probe.agent.tool_results(server).get("t2", "")
            probe.check("UI streaming does not consume wait output", "STREAM_TWO" in result)
            (project / "finish").touch()
            terminal.until(lambda: bool(re.search(re.escape("[" + label + "] failed") + r".*\[7\] ✗", terminal.text())))
            terminal.repaint()
            completion = [text for text in terminal.screen.display if "[" + label + "] failed" in text]
            probe.check("exactly one leading completion with trailing exit metadata", len(completion) == 1
                        and completion[0].rstrip().endswith("[7] ✗") and "2 lines" in completion[0])
            row = next(i for i, text in enumerate(terminal.screen.display) if "[" + label + "] failed" in text)
            cell = terminal.screen.buffer[row][1]
            probe.check("completion is italic", cell.italics)
            probe.check("completed job leaves the active list", "1 job" not in terminal.text())
        finally:
            if terminal:
                terminal.send(b"/quit\r")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if select.select([terminal.fd], [], [], .1)[0]:
                        try:
                            if not os.read(terminal.fd, 65536):
                                break
                        except OSError:
                            break
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
