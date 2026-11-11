#!/usr/bin/env python3
"""The folder ask works in, on the status line (notes n6 and n63), through the real binary and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-status-path.py .build/release/ask

By default the last folder sits right after the mark; `ui.statusPath` "full" shows the whole path, "off" none; at a narrow width the
folder goes before the model's name. The build before shows no folder.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def status(extra, columns=110):
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/shop-project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        ui = {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"}
        ui.update(extra)
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": ui}, file)
        server = agent.Server([])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8")
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=columns)
            terminal.until(lambda: "ask>" in terminal.text() and "anthropic" in terminal.text())
            line = next(row for row in terminal.screen.display if "anthropic" in row or "sonnet" in row)
            return line.rstrip(), project
        except (AssertionError, StopIteration, ValueError, IndexError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def check(label, condition, line):
    if not condition:
        print(f"the status line: {line!r}", file=sys.stderr)
    folding.check(label, condition)


def main():
    line, _ = status({})
    check("by default the last folder, right after the mark", " · shop-project · anthropic/" in line, line)
    line, project = status({"statusPath": "full"}, columns=220)
    check("full: the whole path, where it fits", f" · {project} · anthropic/" in line, line)
    line, _ = status({"statusPath": "full"})
    check("full, where it does not: the last folder", " · shop-project · anthropic/" in line, line)
    line, _ = status({"statusPath": "off"})
    check("off: no folder", "shop-project" not in line, line)
    line, _ = status({"statusPathSide": "trailing"})
    check("trailing: last on the line", line.endswith("shop-project"), line)
    line, _ = status({}, columns=36)
    check("narrow: the folder goes before the model's name", "shop-project" not in line and "sonnet" in line, line)


if __name__ == "__main__":
    main()
