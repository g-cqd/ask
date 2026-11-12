#!/usr/bin/env python3
"""`ui.historyLimit` (note n29) through the real binary and a PTY, on resumed sessions.

Scripts/probe-history-limit.py .build/release/ask

A: 40 messages resumed with a limit of 6: scrolled to the top, a line says how many earlier blocks are not shown, and none of them
is drawn.
B: 20,000 blocks resumed, with a limit of 200 and with none: the resident memory once the screen is up, and how long it took;
the numbers are printed, since the limit was measured to save nothing there (the session holds every entry).
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent

FILLER = " A sentence of ordinary length, said again so that each block holds what a real reply does." * 6


def write_session(state, project, turns):
    directory = os.path.join(state, "ask", "sessions", project.replace("/", "-").lstrip("-"))
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "history.jsonl"), "w") as archive:
        archive.write('{"type":"session","version":1}\n')
        for index in range(turns * 2):
            kind = "user" if index % 2 == 0 else "assistant"
            text = ("Step " if kind == "user" else "Reply ") + str(index) + "," + ("" if kind == "user" else FILLER)
            record = {"type": "entry", "id": str(index), "payload": {"kind": kind, "text": text}}
            if index:
                record["parent"] = str(index - 1)
            archive.write(json.dumps(record, separators=(",", ":")) + "\n")


def resumed(turns, limit, scroll=False):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = os.path.realpath(root) + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        ui = {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off", "historyLimit": limit}
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": ui}, file)
        write_session(state, project, turns)
        server = agent.Server([])
        environment = agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8")
        terminal = None
        try:
            started = time.monotonic()
            terminal = folding.Terminal(project, environment, columns=110, resume=True)
            last = f"Reply {turns * 2 - 1},"
            terminal.until(lambda: "ask>" in terminal.text() and last in terminal.text())
            seconds = time.monotonic() - started
            time.sleep(1)
            terminal.pump()
            rss = int(subprocess.run(["ps", "-o", "rss=", "-p", str(terminal.pid)], capture_output=True, text=True).stdout)
            text = ""
            if scroll:
                for _ in range(12):
                    terminal.send(b"\x1b[5~")
                    for _ in range(5):
                        terminal.pump()
                time.sleep(0.5)
                terminal.pump()
                text = terminal.text()
            return seconds, rss, text
        except (AssertionError, StopIteration, ValueError, IndexError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def main():
    check = folding.check
    _, _, top = resumed(20, 6, scroll=True)
    # The resume adds a notice of its own after the 40 messages, so the count is read, not assumed.
    said = re.search(r"(\d+) earlier blocks are not shown \(ui\.historyLimit\)", top)
    check("A: at the top, a line says how many earlier blocks are not shown", said is not None and int(said.group(1)) >= 34)
    gone = int(said.group(1))
    first = ("Step " if gone % 2 == 0 else "Reply ") + f"{gone},"
    check("A: none of them is drawn, and the first kept one is",
          "Step 0," not in top and f"{gone - 1}," not in top and first in top)
    limited = resumed(10_000, 200)
    unlimited = resumed(10_000, None)
    print(f"INFO B: limit 200: {limited[0]:.1f} s to the screen, {limited[1] / 1024:.0f} MiB resident; "
          f"no limit: {unlimited[0]:.1f} s, {unlimited[1] / 1024:.0f} MiB")
    # Not a check: measured 2026-11-11, the limit saves nothing here (58 against 59 MiB; 105 and 105 at 60,000 blocks). The session
    # itself holds every entry in memory, and the screen's copy of a message shares its text.


if __name__ == "__main__":
    main()
