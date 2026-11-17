#!/usr/bin/env python3
"""Which tools models call wrongly, read from the sessions on this machine: calls and failed calls per tool, and what failed.

    python3 Scripts/measure-tool-errors.py [SESSIONS_DIRECTORY]

It reads the plain session files under ~/.local/state/ask/sessions (never writes), pairs each tool call with its result, and sorts the
results marked as errors into what a better description could have prevented and what it could not:

    arguments   the call's shape was refused: a field the tool does not take, a value outside its limits, a mode mixed with another
    not found   a file, a job or a server that is not there under the name given
    checked     a command refused before it ran: it does not parse, or shellcheck found fault with it
    outcome     the call was right and the world said no: an exit status, a timeout, a page that answered 404, a job that ended

Paths and numbers are taken out of what is printed. A session that is compressed or encrypted is counted and left alone.
"""
import collections
import glob
import json
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/state/ask/sessions")
KINDS = ["arguments", "not found", "checked", "outcome"]
ARGUMENTS = ("Invalid arguments", "Refused, nothing changed", "Give ", "Use content alone", "new_text is required",
             "old_text must not", "Question ", "Invalid sandbox", "old_text occurs", "old_text was not found")
NOT_FOUND = ("No file at", "No job named", "No connected server", "Cannot read", "No skill")
CHECKED = ("shellcheck found", "The command does not parse", "fish:", "zsh:", "bash: -c:")


def kind(text):
    if text.startswith(ARGUMENTS):
        return "arguments"
    if text.startswith(NOT_FOUND):
        return "not found"
    if text.startswith(CHECKED):
        return "checked"
    return "outcome"


def shape(text):
    """The first line of what a failed call said, without the paths and numbers that make each one different."""
    line = re.sub(r"/[\w./+\-@]+", "PATH", text.strip().split("\n")[0])
    return re.sub(r"\d+", "N", line)[:100]


def main():
    calls, failed = collections.Counter(), collections.Counter()
    kinds, said = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    files, left = glob.glob(os.path.join(ROOT, "*", "*.jsonl")), 0
    for path in files:
        with open(path, "rb") as session:
            if not session.readline().startswith(b'{"type":"session"'):
                left += 1
                continue
            pending = {}
            for line in session:
                try:
                    payload = json.loads(line).get("payload") or {}
                except ValueError:
                    continue
                if payload.get("kind") == "response":
                    for block in payload.get("blocks", []):
                        if block.get("type") == "tool_call":
                            calls[block["name"]] += 1
                            pending[block.get("id")] = block["name"]
                elif payload.get("kind") == "tool_result" and payload.get("isError"):
                    name = pending.get(payload.get("callID"), "?")
                    content = payload.get("content")
                    text = content if isinstance(content, str) else json.dumps(content)
                    failed[name] += 1
                    kinds[name][kind(text)] += 1
                    said[name][f"{kind(text)}: {shape(text)}"] += 1
    print(f"{len(files)} session files, {left} not plain; {sum(calls.values())} calls, {sum(failed.values())} failed")
    print(f"{'tool':30}{'calls':>8}{'failed':>8}" + "".join(f"{name:>11}" for name in KINDS))
    for name, count in calls.most_common():
        if count < 5 and not failed[name]:
            continue
        print(f"{name[:29]:30}{count:8}{failed[name]:8}" + "".join(f"{kinds[name][each]:11}" for each in KINDS))
    for name, _ in failed.most_common():
        print(f"\n{name}")
        for line, count in said[name].most_common(8):
            print(f"  {count:5}  {line}")


if __name__ == "__main__":
    main()
