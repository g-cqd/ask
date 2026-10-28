#!/usr/bin/env python3
"""Full input, embedded heredoc folds and replay through the real CLI and PTY/pyte.

ASK_PYTE='' /tmp/ask-job-pty/bin/python Scripts/probe-tool-input.py BINARY
A local scripted provider; no credentials or external network calls.
"""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

spec = importlib.util.spec_from_file_location("folding", Path(__file__).with_name("probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        Path(config + "/ask/config.json").write_text(json.dumps({"ui": {"prompt": "ask> ", "tools": "folded"}}))
        command = "cat << 'EOF' > note.txt\n" + "\n".join(f"payload{i}" for i in range(45)) + "\nEOF\nprintf DONE"
        server = probe.agent.Server([
            probe.agent.turn([("call", "t1", "bash", {"command": command, "shell": "/bin/bash", "timeout_seconds": 5})], "tool_use"),
            probe.agent.turn([("text", "ANSWER")], "end_turn")
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = probe.Terminal(project, environment, rows=80)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Go\r")
            terminal.until(lambda: b"ANSWER" in terminal.raw)
            terminal.repaint()
            probe.check("canonical bash calls are presented as shell, the limits before the command",
                        "shell · timeout 5 sec · cat" in terminal.text())
            probe.check("full tool input starts inside the folded block", "payload0" not in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x0f"))
            probe.check("expanded tool shows input and output without decorative divider labels",
                        "DONE" in terminal.text() and "payload19" in terminal.text()
                        and "── input ──" not in terminal.text() and "── output ──" not in terminal.text())
            probe.check("a 45-line heredoc keeps twenty lines and identifies twenty-five omitted",
                        "payload19" in terminal.text() and "25 lines embedded heredoc" in terminal.text()
                        and "payload44" not in terminal.text() and "printf DONE" in terminal.text())
            terminal.draw(lambda: terminal.click("embedded heredoc"))
            probe.check("a click opens the heredoc without closing the whole tool",
                        "payload44" in terminal.text() and "DONE" in terminal.text())
            first, last = terminal.row("payload42") + 1, terminal.row("payload44") + 1
            terminal.send(f"\x1b[<0;1;{first}M\x1b[<32;10;{last}M\x1b[<0;10;{last}m".encode())
            terminal.until(lambda: bool(terminal.copies()))
            probe.check("input copying excludes labels and indentation", terminal.copies()[-1] == "payload42\npayload43\npayload44")
            terminal.close()
            terminal = probe.Terminal(project, environment, resume=True, rows=80)
            terminal.until(lambda: "ANSWER" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x0f"))
            probe.check("replay retains input and default heredoc folds", "payload19" in terminal.text()
                        and "25 lines embedded heredoc" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x07"))
            probe.check("Ctrl G expands replayed heredoc input", "payload44" in terminal.text())
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
