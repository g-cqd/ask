#!/usr/bin/env python3
"""What a search that changes the tool list costs: the cache read by the request after each MCP search, from the sessions here.

    python3 Scripts/measure-cache-after-search.py [--sessions DIRECTORY]

It reads the plain session files under ~/.local/state/ask/sessions (never writes). A provider's prompt cache starts with the
tool list, so a search whose matches are then offered as tools should make the next request read nothing from the cache, and a
search that offers nothing new (no words, no match, or the same words again) should not. It prints each search with the tokens
the next request read from the cache, its whole input and the model, and how often a request that follows no search misses. A response is
counted once however many sessions carry it (a resumed session repeats its past).
"""
import collections
import glob
import json
import os
import sys

SEARCHES = ("search_catalog", "mcp_search")
# Under this many input tokens a provider may not cache at all, and a miss says nothing.
FLOOR = 30_000


def responses(path):
    with open(path, "rb") as session:
        if not session.readline().startswith(b'{"type":"session"'):
            return
        for line in session:
            try:
                payload = json.loads(line).get("payload") or {}
            except ValueError:
                continue
            if payload.get("kind") == "response":
                yield payload


def searched(response):
    for block in response.get("blocks", []):
        if block.get("type") == "tool_call" and block.get("name") in SEARCHES:
            given = block.get("input")
            return given if isinstance(given, str) else json.dumps(given)
    return None


def main():
    root = os.path.expanduser("~/.local/state/ask/sessions")
    if "--sessions" in sys.argv:
        root = sys.argv[sys.argv.index("--sessions") + 1]
    seen, rows, others = set(), [], collections.Counter()
    for path in sorted(glob.glob(os.path.join(root, "*", "*.jsonl"))):
        before, asked = None, set()
        for response in responses(path):
            usage = response.get("usage") or {}
            read = usage.get("cacheRead", 0)
            whole = usage.get("input", 0) + read + usage.get("cacheCreation", 0)
            query = searched(before) if before else None
            if response.get("id") not in seen and whole >= FLOOR:
                if query is None:
                    others["missed" if read == 0 else "read"] += 1
                else:
                    rows.append((query, "again" if query in asked else "first", read, whole, response.get("model", "")))
            if query is not None:
                asked.add(query)
            seen.add(response.get("id"))
            before = response
    print(f"{'the search':58} {'asked':6} {'cache read':>11} {'of input':>9}  model")
    for query, order, read, whole, model in rows:
        print(f"{query[:58]:58} {order:6} {read:>11,} {whole:>9,}  {model}")
    total = others["missed"] + others["read"]
    share = 100 * others["missed"] / total if total else 0
    print(f"\nA request after no search read nothing from the cache {others['missed']:,} times in {total:,} ({share:.1f}%).")


if __name__ == "__main__":
    main()
