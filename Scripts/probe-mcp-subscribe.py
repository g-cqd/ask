#!/usr/bin/env python3
"""Probe a followed resource (the owner's choice, 2026-11-02, roadmap 0067) through the real binary, a PTY, a local fake provider and the
fixture server in its `resources` mode, which says a resource changed as soon as it is subscribed to.

Scripts/probe-mcp-subscribe.py .build/release/ask

A message attaching `@fx:note://a` subscribes to it; the server's change is told to the person, naming the reference to send again, and
the model is sent nothing more.
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
    servers = lambda project: {"mcp": {"fx": {"command": "python3", "args": [ms.FIXTURE, "resources"]}}}
    with pp.Session(binary, [pp.short_answer("Noted.")], settings=servers) as session:
        terminal = session.terminal
        ms.send(session, "Keep @fx:note://a in mind", "Noted.")
        terminal.until(lambda: b"changed since it was attached" in bytes(terminal.raw))
        flat = " ".join(line.strip() for line in ms.screen(terminal).split("\n"))
        pp.check("the change is told, naming what to send again", "@fx:note://a changed since it was attached" in flat)
        pp.check("the model was sent one request, nothing for the change", session.requests() == 1)
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
