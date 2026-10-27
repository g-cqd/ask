#!/usr/bin/env python3
"""Command reports are one padded block, not a padded block per entry.

Run against the shipping binary. The oversized PTY keeps reports in view, and
we inspect adjacent rendered rows rather than whitespace in raw escape bytes.
Usage: python3 Scripts/probe-command-spacing.py .build/release/ask
"""
import importlib.util
import os
import sys
import tempfile

spec = importlib.util.spec_from_file_location(
    "interactive", os.path.join(os.path.dirname(__file__), "probe-interactive.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
probe.ROWS = 220
probe.COLUMNS = 200


def report_rows(screen, command):
    screen.type(command + "\r")
    screen.until("\x00", 0.8)
    rows = screen.screen.text().splitlines()
    start = max(i for i, row in enumerate(rows) if row.strip() == command)
    end = next(i for i in range(start + 1, len(rows)) if rows[i].startswith("─"))
    body = rows[start + 1:end]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return body


def main():
    server = probe.agent.Server([
        probe.agent.turn([("text", "FIRST REPLY")], "end_turn"),
        probe.agent.turn([("text", "SECOND REPLY")], "end_turn")])
    screen = probe.Screen(server.url, tempfile.mkdtemp())
    results = []
    try:
        assert screen.until("────"), "initial frame missing"
        screen.type("first prompt\r")
        assert screen.until("FIRST REPLY"), "first reply missing"
        screen.type("second prompt\r")
        assert screen.until("SECOND REPLY"), "second reply missing"
        for command in ("/help", "/config", "/mcp", "/resume", "/tree"):
            rows = report_rows(screen, command)
            results.append(probe.check(
                command + " has content without blank rows between its entries",
                bool(rows) and all(row.strip() for row in rows), repr(rows)))
        return all(results)
    finally:
        screen.type("\x03\x03")
        screen.finish(3)
        server.httpd.shutdown()


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
