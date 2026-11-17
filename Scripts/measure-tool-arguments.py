#!/usr/bin/env python3
"""Which arguments models give each tool, read from the sessions on this machine: the calls per tool and per set of arguments.

    python3 Scripts/measure-tool-arguments.py [TOOL ...] [--sessions DIRECTORY] [--values FIELD ...]

It reads the plain session files under ~/.local/state/ask/sessions (never writes) and counts, for each tool named (every tool
when none is), how often each argument was given and each combination of them. --values counts what a field held, for a field
that is a choice (job's action, a view). It answers what a consolidation needs: whether an argument is used at all, and with what.
"""
import collections
import glob
import json
import os
import sys


def options(arguments):
    tools, values, root, into = [], [], os.path.expanduser("~/.local/state/ask/sessions"), None
    for word in arguments:
        if word in ("--sessions", "--values"):
            into = word
        elif into == "--sessions":
            root, into = word, None
        elif into == "--values":
            values.append(word)
        else:
            tools.append(word)
    return tools, values, root


def inputs(root):
    """Every tool call's name and decoded input, from the plain sessions under `root`."""
    for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
        with open(path, "rb") as session:
            if not session.readline().startswith(b'{"type":"session"'):
                continue
            for line in session:
                try:
                    payload = json.loads(line).get("payload") or {}
                except ValueError:
                    continue
                if payload.get("kind") != "response":
                    continue
                for block in payload.get("blocks", []):
                    if block.get("type") != "tool_call":
                        continue
                    given = block.get("input")
                    try:
                        given = json.loads(given) if isinstance(given, str) else given
                    except ValueError:
                        given = None
                    yield block["name"], given if isinstance(given, dict) else {}


def main():
    tools, values, root = options(sys.argv[1:])
    calls, fields = collections.Counter(), collections.defaultdict(collections.Counter)
    shapes, held = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    for name, given in inputs(root):
        if tools and name not in tools:
            continue
        calls[name] += 1
        fields[name].update(given.keys())
        shapes[name][" ".join(sorted(given.keys())) or "(none)"] += 1
        for field in values:
            if field in given and isinstance(given[field], (str, int, bool)):
                held[name][f"{field}={given[field]}"] += 1
    for name, count in calls.most_common():
        print(f"{name}: {count} calls")
        print("  given:  " + ", ".join(f"{field} {times}" for field, times in fields[name].most_common()))
        for shape, times in shapes[name].most_common(12):
            print(f"  {times:7}  {shape}")
        for value, times in held[name].most_common(12):
            print(f"  {times:7}  {value}")


if __name__ == "__main__":
    main()
