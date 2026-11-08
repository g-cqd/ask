#!/usr/bin/env python3
"""Probe paths in replies (roadmap 0215) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-reply-paths.py .build/release/ask

The model's reply names a file of the project by its absolute path, with a line, and another by a relative path; it also names a relative
path that does not exist. The reply shows the first relative to the project, links both that exist as ask's own OSC 8, and leaves the
missing one plain. The person's message keeps its absolute path as written. The build before shows the absolute path. Requires pyte:
ask's bytes through an emulator, not a physical terminal.
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


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/project", root + "/config"
        os.makedirs(project + "/Sources")
        os.makedirs(config + "/ask")
        for name in ("Sources/a.swift", "Package.swift"):
            with open(os.path.join(project, name), "w") as file:
                file.write("// probe\n")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","tint":"off","separator":"off","padding":"off"}}')
        absolute = project + "/Sources/a.swift"
        reply = f"Fixed {absolute}:12 and Package.swift, but not Missing.swift."
        server = agent.Server([agent.turn([("text", reply)], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=200)
            terminal.until(lambda: "ask>" in terminal.text())
            beginning = len(terminal.raw)
            terminal.send(f"see {absolute}\r".encode())
            terminal.until(lambda: "Missing.swift" in terminal.text())
            terminal.repaint()
            text = terminal.text()
            raw = bytes(terminal.raw)[beginning:]
            if os.environ.get("PROBE_SHOW"):
                print(text)
            check("the reply shows the project's file relative to it, with its line",
                  "Fixed Sources/a.swift:12 and Package.swift, but not Missing.swift." in text)
            check("the person's own message keeps the absolute path", f"see {absolute}" in text)
            links = re.findall(rb"\x1b\]8;[^;\x07\x1b]*;([^\x07\x1b]*)", raw)
            if os.environ.get("PROBE_SHOW"):
                print(links)
            # ask writes a link's path standardised, as macOS's /private/var is /var: the same file either way.
            plain = {link.replace(b"file:///private/", b"file:///") for link in links}
            unprivate = project.replace("/private/", "/", 1)
            check("both files are linked to the project's files",
                  f"file://{unprivate}/Sources/a.swift".encode() in plain and f"file://{unprivate}/Package.swift".encode() in plain)
            check("the missing file is not linked", not any(b"Missing.swift" in link for link in links))
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
