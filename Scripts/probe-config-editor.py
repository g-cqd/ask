#!/usr/bin/env python3
"""The interactive configuration editor through the real binary, a PTY and a local fake provider.

ASK_PYTE='' /tmp/ask-job-pty/bin/python Scripts/probe-config-editor.py BINARY
Hermetic: ask's configuration follows $XDG_CONFIG_HOME; no real file is touched.
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
        Path(config + "/ask/config.json").write_text(
            '// a comment the editor does not keep\n{\n  "maxTurns": 40,\n  "thinking": "low",\n  "ui": {\n    "tint": "off",\n    "inputPrefix": "ask> ",\n    "scrollLines": 2\n  }\n}\n')
        server = probe.agent.Server([probe.agent.turn([("text", "OK")], "end_turn")])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        terminal = probe.Terminal(project, environment, columns=100, rows=40)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/config\r")
            terminal.until(lambda: "user" in terminal.text() and "project" in terminal.text())
            probe.check("a bare /config offers the user and project scopes", "user" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\r"))
            terminal.until(lambda: "ui.tint" in terminal.text())
            probe.check("the editor lists editable settings with their current values", "ui.tint" in terminal.text())
            probe.check("the editor opens with the first editable row selected and its value shown",
                        "ui.mouse" in terminal.text())
            probe.check("the editor's caption explains its keys", "Enter saves" in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x1b[B\x1b[B"))
            terminal.draw(lambda: terminal.send(b"\x1b[C"))
            terminal.draw(lambda: terminal.send(b"\r"))
            terminal.until(lambda: b"Saved" in terminal.raw)
            saved = Path(config + "/ask/config.json").read_text()
            probe.check("the save changes only the edited key and keeps every other setting",
                        '"tint": true' in saved and "maxTurns" in saved and "scrollLines" in saved
                        and "thinking" in saved and "mouse" not in saved and "model" not in saved)
            probe.check("the save is strict JSON with no comment left", "//" not in saved and " {" in saved)
            terminal.send(b"\x1b")
            terminal.until(lambda: "ask>" in terminal.text())
            probe.check("escape closes the editor and returns to the prompt", "ui.spinner" not in terminal.text())
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
