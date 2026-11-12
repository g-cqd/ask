#!/usr/bin/env python3
"""Probe the swift preset (roadmap 0190) through the real binary, a PTY and a local fake provider; apple-docs needs the network.

Scripts/probe-mcp-preset.py .build/release/ask [--without-swift-search]

`"presets": ["swift"]` and nothing else: after the first message `/mcp` lists apple-docs and swift-search as ready, and the first
request offers their tools. With --without-swift-search the PATH has no swift-search: apple-docs still connects, and the turn says
swift-search could not start.
"""
import importlib.util
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcp_screen", os.path.join(HERE, "probe-mcp-screen.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)
sys.argv = saved
pp = ms.pp
WITHOUT = "--without-swift-search" in sys.argv
# Where swift-search is not installed the preset cannot start it: probe what that looks like rather than fail for it.
if not WITHOUT and shutil.which("swift-search") is None:
    print("swift-search is not on the PATH: probing the preset without it", flush=True)
    WITHOUT = True


def main():
    binary = os.path.abspath(sys.argv[1])
    if WITHOUT:
        os.environ["PATH"] = ":".join(d for d in os.environ["PATH"].split(":")
                                       if not os.path.exists(os.path.join(d, "swift-search")))
    with pp.Session(binary, [pp.short_answer("ANSWER ONE")], settings=lambda project: {"presets": ["swift"]}) as session:
        terminal = session.terminal
        ms.send(session, "hello", "ANSWER ONE")
        terminal.until(lambda: b"connected" in bytes(terminal.raw))
        ms.send(session, "/mcp", "apple-docs:")
        shown = ms.screen(terminal)
        flat = " ".join(line.strip() for line in shown.split("\n"))
        pp.check("apple-docs connects from the preset", "apple-docs: ready" in flat)
        tools = [t["name"] for t in session.server.requests[0]["body"].get("tools", [])]
        if WITHOUT:
            pp.check("without swift-search on the PATH, it is said not to start", "swift-search: not connected" in flat
                     or "is not found or cannot be executed" in flat)
        else:
            pp.check("swift-search connects from the preset", "swift-search: ready" in flat)
            pp.check("the first request offers a swift-search tool", any(name.startswith("mcp__swift-search__") or
                                                                          name.startswith("mcp__swift_search__") for name in tools))
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
