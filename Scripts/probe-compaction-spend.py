#!/usr/bin/env python3
"""Check that a compaction says what the work it summarised cost, beside the stretch before (roadmap 0239), through the real binary,
a PTY and a scripted provider.

Scripts/probe-compaction-spend.py .build/release/ask

Stretch one: the model reads a file and answers, then a pasted prompt larger than the 80 KB tail a compaction keeps, then `/compact`:
a line says `Worked before this compaction: 3 requests, 1 tool`. Stretch two: two prompts, the second as large, then `/compact`: the
line says `Worked since the previous compaction: 2 requests` and `the stretch before: 3 requests, 1 tool`. pyte, not a physical
terminal.
"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check


class Scripted:
    """Answers each request with the next of `answers`, each `(delay, body)`; the last answer is repeated."""

    def __init__(self, answers):
        self.answers, self.count, self.hold = answers, 0, threading.Event()
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers["content-length"]))
                delay, body = outer.answers[min(outer.count, len(outer.answers) - 1)]
                outer.count += 1
                if delay == "hold":
                    outer.hold.wait(10)
                else:
                    time.sleep(delay)
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"



def paste(terminal, text):
    data = b"\x1b[200~" + text.encode() + b"\x1b[201~"
    for start in range(0, len(data), 4096):
        terminal.send(data[start:start + 4096])
        terminal.pump()


def line(terminal, prefix):
    return next((row.strip() for row in terminal.text().splitlines() if row.strip().startswith(prefix)), "")


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(project + "/notes.txt", "w") as file:
            file.write("hello\n")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","separator":"off","localizedDurations":false}}')
        server = Scripted([
            (0, agent.turn([("call", "c1", "read", {"path": "notes.txt"})], "tool_use", input_tokens=1200)),
            (0.5, agent.turn([("text", "FIRST DONE")], "end_turn", input_tokens=1300)),
            (0, agent.turn([("text", "BIG ONE READ")], "end_turn", input_tokens=30_000)),
            (0, agent.turn([("text", "SUMMARY ONE")], "end_turn", input_tokens=31_000)),
            (0, agent.turn([("text", "THIRD DONE")], "end_turn", input_tokens=500)),
            (0, agent.turn([("text", "BIG TWO READ")], "end_turn", input_tokens=30_000)),
            (0, agent.turn([("text", "SUMMARY TWO")], "end_turn", input_tokens=31_000)),
        ])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment, columns=160)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Read the notes\r")
            terminal.until(lambda: "FIRST DONE" in terminal.text())
            paste(terminal, "Background: " + "lorem ipsum " * 7_500)
            terminal.send(b"\r")
            terminal.until(lambda: "BIG ONE READ" in terminal.text())
            terminal.send(b"/compact\r")
            terminal.until(lambda: "Worked before this compaction" in terminal.text())
            first = line(terminal, "Worked before this compaction")
            print("first:", first)
            check("the first compaction says its stretch: three requests, one tool",
                  first.startswith("Worked before this compaction: 3 requests, 1 tool · ↑"))
            terminal.send(b"Go on\r")
            terminal.until(lambda: "THIRD DONE" in terminal.text())
            paste(terminal, "More: " + "dolor sit " * 9_000)
            terminal.send(b"\r")
            terminal.until(lambda: "BIG TWO READ" in terminal.text())
            terminal.send(b"/compact\r")
            terminal.until(lambda: "; the stretch before: " in terminal.text() and "tool" in line(terminal, "Worked since"))
            second = line(terminal, "Worked since the previous compaction")
            print("second:", second)
            check("the next compares its own two requests with the stretch before",
                  second.startswith("Worked since the previous compaction: 2 requests · ↑")
                  and "; the stretch before: 3 requests, 1 tool · ↑" in second)
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
