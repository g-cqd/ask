#!/usr/bin/env python3
"""Probe a server's progress in the screen (roadmap 0067) through the real binary, a PTY, a local fake provider and the fixture server.

Scripts/probe-mcp-progress.py .build/release/ask

A call to the fixture's echo with `slow` is told "half way" by the server and then waits: while it waits, the block's header says
`50% · half way`; when it ends, the header no longer does.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcp_screen", os.path.join(HERE, "probe-mcp-screen.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)
sys.argv = saved
pp = ms.pp


def main():
    binary = os.path.abspath(sys.argv[1])
    turns = [
        pp.probe.agent.turn([("call", "p1", "mcp__fx__echo", {"message": "hi", "slow": 3})], "tool_use"),
        pp.short_answer("Echoed."),
    ]
    with pp.Session(binary, turns, settings=ms.servers) as session:
        terminal = session.terminal
        ms.send(session, "Echo slowly.", "half way")
        shown = ms.screen(terminal)
        header = next((line for line in shown.split("\n") if "half way" in line), "")
        pp.check("while the call runs, its header says how far the server has got", "50% · half way" in header and "echo" in header)
        terminal.until(lambda: "Echoed." in terminal.text())
        shown = ms.screen(terminal)
        pp.check("when it ends, the note is gone", "half way" not in shown and "Echoed." in shown)
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
