#!/usr/bin/env python3
"""Probe the MCP servers in the screen (ADR-0099) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-mcp-screen.py .build/release/ask [--control OLDER_BINARY]

The servers connect while the person has not typed anything, and the screen says so; `/mcp` lists them; a server that cannot start
is said once and the screen still works; /help lists the command. With --control, a binary that predates the feature does not know
`/mcp`: a probe that cannot fail is not a probe.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "..", "Tests", "AskMCPTests", "Fixtures", "fixture-server.py")
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
sys.argv = saved
check, press, type_text, rows = pp.check, pp.press, pp.type_text, pp.rows


def screen(terminal):
    terminal.repaint()
    return "\n".join(rows(terminal))


def send(session, text, expect):
    terminal = session.terminal
    type_text(terminal, text)
    press(terminal, b"\r")
    terminal.until(lambda: expect in terminal.text())


def servers(project):
    return {"mcp": {"fx": {"command": "python3", "args": [FIXTURE]}, "ghost": {"command": "/nonexistent/mcp-server"}}}


def main():
    binary = os.path.abspath(sys.argv[1])
    turns = [pp.short_answer("ANSWER ONE")]
    if "--control" in sys.argv:
        with pp.Session(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]), turns) as session:
            send(session, "/mcp", "There is no command /mcp")
            check("control (a binary before MCP): the command is not known", "There is no command /mcp" in screen(session.terminal))
        return
    with pp.Session(binary, turns, settings=servers) as session:
        terminal = session.terminal
        # The raw bytes, not the emulated screen: pyte does not do scroll regions, so only a repaint (`screen`) is a faithful picture.
        terminal.until(lambda: b"MCP server fx connected" in bytes(terminal.raw) and b"did not start" in bytes(terminal.raw))
        shown = screen(terminal)
        flat = " ".join(line.strip() for line in shown.split("\n"))  # a long notice wraps
        check("the screen says the server connected, without anyone typing", "MCP server fx connected: 5 of 5 tools offered" in shown)
        check("and that the other did not start, and why", "MCP server ghost did not start" in flat and "is not found or cannot be executed" in flat)

        send(session, "/mcp", "fx: ready")
        shown = screen(terminal)
        check("/mcp lists each server and where it stands", "fx: ready, 5 of 5 tools offered" in shown and "ghost: not connected" in shown)

        send(session, "/help", "/mcp")
        check("/help lists the command", "/mcp" in screen(terminal))

        send(session, "hello", "ANSWER ONE")
        first = session.server.requests[0]["body"]["tools"]
        check("the first request already offers the server's tools", any(t["name"] == "mcp__fx__echo" for t in first))
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
