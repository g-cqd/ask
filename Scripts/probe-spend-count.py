#!/usr/bin/env python3
"""Check what ask says a session spent against an independent count of the same log (roadmap 0239, step 0's "done when").

Scripts/probe-spend-count.py [SESSION.jsonl ...]

ccusage reads Claude Code's logs, not ask's, so the independent count is this script: it reads each plain session log line by line,
follows its active branch from the last leaf, and sums the responses, their tokens and the tool results, and the time before each, as
roadmap 0239 defines them. Then `SpendIndependentCountTests`, through ask's own loader and `WorkSpend`, must find the same figures.
With no argument it takes the five largest plain logs in ask's sessions folder. It reads sessions and never writes them.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile


def count(path):
    parent, leaf, entries = {}, None, {}
    with open(path, "rb") as file:
        for line in file:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get("type") == "leaf":
                leaf = record.get("id")
            elif record.get("type") == "entry":
                parent[record["id"]] = record.get("parent")
                entries[record["id"]] = record
                leaf = record["id"]
    branch = []
    while leaf is not None:
        branch.append(entries[leaf])
        leaf = parent[leaf]
    branch.reverse()
    figures = dict(requests=0, tools=0, input=None, output=None, cacheRead=None, cacheCreation=None, model=None, tool=None)
    first = previous = None
    for entry in branch:
        payload = entry.get("payload", {})
        kind = payload.get("kind")
        if kind == "response":
            figures["requests"] += 1
            for key, value in (payload.get("usage") or {}).items():
                if key in ("input", "output", "cacheRead", "cacheCreation") and value is not None:
                    figures[key] = (figures[key] or 0) + value
        if kind == "tool_result":
            figures["tools"] += 1
        time = entry.get("time")
        if time is None:
            continue
        if previous is not None:
            gap = max(0, time - previous)
            if kind == "response":
                figures["model"] = (figures["model"] or 0) + gap
            elif kind == "tool_result":
                figures["tool"] = (figures["tool"] or 0) + gap
        first = time if first is None else first
        previous = time
    wall = previous - first if first is not None and previous > first else None
    order = [figures["requests"], figures["tools"], figures["input"], figures["output"], figures["cacheRead"],
             figures["cacheCreation"], wall, figures["model"], figures["tool"]]
    return ",".join("nil" if value is None else str(value) for value in order), len(branch)


def plain(path):
    with open(path, "rb") as file:
        return file.readline().startswith(b'{"type":"session"')


def main():
    paths = sys.argv[1:]
    if not paths:
        state = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
        logs = [p for p in glob.glob(state + "/ask/sessions/*/*.jsonl") if plain(p)]
        paths = sorted(logs, key=os.path.getsize, reverse=True)[:5]
    checks = []
    for path in paths:
        expect, length = count(path)
        print(f"{os.path.basename(path)}: {length} entries on the branch, counted {expect}")
        checks.append({"path": path, "expect": expect})
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as file:
        json.dump(checks, file)
    environment = dict(os.environ, ASK_SPEND_CHECK=file.name)
    run = subprocess.run(["swift", "test", "-c", "release", "--enable-testable-imports", "--filter", "SpendIndependentCount"],
                         env=environment, capture_output=True, text=True)
    os.unlink(file.name)
    report = [line for line in (run.stdout + run.stderr).splitlines() if "recorded an issue" in line or "Test run with" in line
              or "Expectation failed" in line]
    print("\n".join(report[-12:]))
    ran = any("Test run with 1 test" in line for line in report)
    print("PASS: ask's totals agree with the independent count" if run.returncode == 0 and ran else "FAIL")
    sys.exit(0 if run.returncode == 0 and ran else 1)


if __name__ == "__main__":
    main()
