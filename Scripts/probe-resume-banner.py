#!/usr/bin/env python3
"""Check the clean-exit resume command and terminal hyperlink against spaces and quotes.

Usage: ASK_PYTE='' /tmp/ask-job-pty/bin/python Scripts/probe-resume-banner.py BINARY
Uses the existing local scripted provider and PTY; no account or network service is needed.
"""
import importlib.util
import os
from pathlib import Path
import shlex
import sys
import tempfile

spec = importlib.util.spec_from_file_location("folding", Path(__file__).with_name("probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)


def main():
    with tempfile.TemporaryDirectory() as root:
        project = root + "/work space's project"
        config = root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        Path(config + "/ask/config.json").write_text('{"ui":{"inputPrefix":"ask> "}}')
        server = folding.agent.Server([folding.agent.turn([("text", "BANNER ANSWER")], "end_turn")])
        environment = folding.agent.environment(root + "/state", server.url, config=config)
        terminal = folding.Terminal(project, environment)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Go\r")
            terminal.until(lambda: b"BANNER ANSWER" in terminal.raw)
            terminal.send(b"/quit\r")
            try:
                terminal.until(lambda: b"To resume:" in terminal.raw)
            except OSError as error:
                raise AssertionError("clean exit did not print a resume command") from error
            raw = bytes(terminal.raw).decode("utf-8", errors="replace")
            assert "\x1b]8;;file://" in raw, "embedded OSC 8 terminal hyperlink missing from output"
            assert "Session saved to " in raw
            command = raw.split("To resume: ", 1)[1].splitlines()[0].strip()
            assert "'ask'" not in command, "command 'ask' should not be quoted"
            assert "'--resume'" not in command, "flag '--resume' should not be quoted"
            lexer = shlex.shlex(command, posix=True, punctuation_chars=";")
            lexer.whitespace_split = True
            tokens = list(lexer)
            assert tokens[0] == "cd" and tokens[2] == ";" and tokens[3] == "ask" and tokens[4] == "--resume", tokens
            resolved_proj = os.path.realpath(project)
            assert tokens[1] == resolved_proj or tokens[1] == project or tokens[1].endswith("/work space's project"), tokens[1]
            session = tokens[5]
            assert Path(session).is_file() or Path(os.path.expanduser(session)).is_file(), session
            print("PASS clean quit prints clickable file link and paste-safe resume command")
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
