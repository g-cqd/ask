#!/usr/bin/env python3
"""Measure loading 1,000 turns in a live screen, or launching directly into that archive.
Usage: python3 development/research/probe-interactive-resume-cost.py .build/release/ask [switch|launch] [turns] [runs]
Isolated configuration, state and project; no credentials or provider requests.
"""
import json
import os
from pathlib import Path
import runpy
import statistics
import sys
import tempfile
import time

binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
mode = sys.argv[2] if len(sys.argv) > 2 else "switch"
turns = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
runs = int(sys.argv[4]) if len(sys.argv) > 4 else 7
assert mode in ("switch", "launch") and turns > 0 and runs >= 4
root = Path(__file__).resolve().parents[2]
sys.argv = ["probe", binary]
probe = runpy.run_path(str(root / "Scripts/probe-interactive.py"))
with tempfile.TemporaryDirectory(prefix="ask-resume-cost-") as project:
    config = os.path.join(project, "config")
    os.makedirs(config)
    path = os.path.join(project, "history.jsonl")
    with open(path, "w") as archive:
        archive.write('{"type":"session","version":1}\n')
        for index in range(turns * 2):
            record = {"type": "entry", "id": str(index), "payload": {
                "kind": "user" if index % 2 == 0 else "assistant",
                "text": ("Prompt " if index % 2 == 0 else "Answer ") + str(index)}}
            if index:
                record["parent"] = str(index - 1)
            archive.write(json.dumps(record, separators=(",", ":")) + "\n")
    values = []
    for _ in range(runs):
        start = time.perf_counter()
        arguments = ("--resume", path) if mode == "launch" else ()
        screen = probe["Screen"]("http://127.0.0.1:1", project, config=config, arguments=arguments)
        try:
            if mode == "switch":
                assert screen.until("ask>"), screen.screen.text()
                start = time.perf_counter()
                screen.type("/resume " + path + "\r")
                assert screen.until("Resumed session history.jsonl", 30), screen.screen.text()
            else:
                assert screen.until("Answer " + str(turns * 2 - 1), 30), screen.screen.text()
            values.append((time.perf_counter() - start) * 1000)
        finally:
            screen.type("/quit\r")
            assert screen.finish() == 0
            os.close(screen.fd)
    quartiles = statistics.quantiles(values, n=4)
    print(mode, turns, "turns,", runs, "runs, ms")
    print("samples:", values)
    print("p50:", statistics.median(values), "IQR:", quartiles[0], quartiles[2])
