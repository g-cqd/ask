#!/usr/bin/env python3
"""Probe the MCP servers in the screen (ADR-0099) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-mcp-screen.py .build/release/ask [--control OLDER_BINARY]

The servers connect while the person has not typed anything, and the screen says so; `/mcp` lists them; a server that cannot start
is said once and the screen still works; /help lists the command. With --control, a binary that predates the feature does not know
`/mcp`: a probe that cannot fail is not a probe.
"""
import importlib.util
import os
import time
import subprocess
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


def fixture_running():
    """How many processes run the fixture server now."""
    found = subprocess.run(["pgrep", "-f", FIXTURE], capture_output=True, text=True).stdout.split()
    return len(found)


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
        # Nothing connects before the first message (roadmap 0143): /mcp says when they will.
        send(session, "/mcp", "fx: connects with the first message")
        time.sleep(1.0)
        shown = screen(terminal)
        check("before the first message no server is started, and /mcp says they connect with it (0143)",
              "fx: connects with the first message" in shown and "MCP server connected" not in shown
              and fixture_running() == 0)

        send(session, "hello", "ANSWER ONE")
        first = session.server.requests[0]["body"]["tools"]
        check("the first request already offers the server's tools", any(t["name"] == "mcp__fx__echo" for t in first))
        # The raw bytes, not the emulated screen: pyte does not do scroll regions, so only a repaint (`screen`) is a faithful picture.
        terminal.until(lambda: b"1 MCP server connected." in bytes(terminal.raw))
        shown = screen(terminal)
        flat = " ".join(line.strip() for line in shown.split("\n"))  # a long notice wraps
        check("the first message's turn says the servers connected in one summary (0145)",
              "1 MCP server connected." in shown and "MCP server fx connected" not in shown)
        check("and, in the same block, that the other failed, and why",
              "1 failed to connect:" in flat and "ghost:" in flat and "is not found or cannot be executed" in flat)

        send(session, "/mcp", "fx: ready")
        shown = screen(terminal)
        check("/mcp lists each server and where it stands", "fx: ready, 7 of 7 tools offered" in shown and "ghost: not connected" in shown)

        send(session, "/help", "/mcp")
        check("/help lists the command", "/mcp" in screen(terminal))

    # A tool the server marks destructive is asked about before it runs (ADR-0111): allow for the session, the grant, and a refusal.
    import tempfile
    victim = os.path.join(tempfile.mkdtemp(), "victim.txt")
    open(victim, "w").write("data")
    turns = [
        pp.probe.agent.turn([("call", "b1", "mcp__fx__boom", {"path": victim})], "tool_use"),
        pp.short_answer("Done one."),
        pp.probe.agent.turn([("call", "b2", "mcp__fx__boom", {"path": victim})], "tool_use"),
        pp.short_answer("Done two."),
        pp.probe.agent.turn([("call", "z1", "mcp__fx__zap", {"path": victim})], "tool_use"),
        pp.short_answer("Done three."),
    ]
    with pp.Session(binary, turns, settings=servers) as asking:
        terminal = asking.terminal
        send(asking, "Use boom.", "Allow it?")
        shown = screen(terminal)
        check("a marked tool is put to the user before it runs",
              "boom" in shown and "read-only" in shown and "Allow this time" in shown and "[✓]  3   Deny" in shown)
        press(terminal, b"a")
        press(terminal, b"\r")
        terminal.until(lambda: "Done one." in terminal.text())
        check("allowing it for the session runs the call", "→ allowed for the session" in screen(terminal))

        send(asking, "again", "Done two.")
        shown = screen(terminal)
        check("a second call of the same tool is not asked about again",
              shown.count("Allow it?") == 1 and "Done two." in shown)

        send(asking, "now zap", "tool zap")
        shown = screen(terminal)
        # The first question may have scrolled off this screen: what counts is that the one now pending is about zap.
        pending = shown[shown.rindex("The MCP server"):] if "The MCP server" in shown else ""
        check("a different marked tool is asked about", "tool zap" in pending and "Allow it?" in pending)
        press(terminal, b"n")
        press(terminal, b"\r")
        terminal.until(lambda: "Done three." in terminal.text())
        shown = screen(terminal)
        check("refusing it says so and the model is told", "→ denied" in shown and "Done three." in shown)
        results = [
            b for r in asking.server.requests for m in r["body"].get("messages", []) for b in m.get("content", [])
            if isinstance(b, dict) and b.get("type") == "tool_result"
        ]
        check("the refusal reached the model as the tool's result",
              any("did not allow" in str(b.get("content")) for b in results))
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
