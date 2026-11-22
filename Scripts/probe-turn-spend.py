#!/usr/bin/env python3
"""Check that the status line says what the last turn cost, through the real binary, a PTY and a scripted provider (roadmap 0239).

Scripts/probe-turn-spend.py .build/release/ask

Turn one: the model reads a file, then answers after 1.5 s. Its end must show `last turn 2 requests, 1 tool`, its tokens and a time of at
least a second. While turn two runs the figure is gone; when it ends, it says turn two's one request. Turn three starts a task, reads,
and marks it done: a line says what the task cost, and `/tasks all` says it after the task's line. pyte, not a physical terminal.
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


def status_line(terminal):
    """The screen's last non-blank line, where the status line sits."""
    return next((line for line in reversed(terminal.screen.display) if line.strip()), "")


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
            (1.5, agent.turn([("text", "FIRST DONE")], "end_turn", input_tokens=1300)),
            ("hold", agent.turn([("text", "SECOND DONE")], "end_turn", input_tokens=40)),
            (0, agent.turn([("call", "c2", "tasks", {"changes": [{"op": "add", "title": "Read the notes", "state": "in_progress"}]})],
                           "tool_use", input_tokens=50)),
            (1.2, agent.turn([("call", "c3", "read", {"path": "notes.txt"})], "tool_use", input_tokens=60)),
            (0, agent.turn([("call", "c4", "tasks", {"changes": [{"op": "state", "ids": "t1", "state": "done"}]})],
                           "tool_use", input_tokens=70)),
            (0, agent.turn([("text", "THIRD DONE")], "end_turn", input_tokens=80)),
        ])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8", COLUMNS="200")
        terminal = folding.Terminal(project, environment, columns=200)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Go\r")
            terminal.until(lambda: "FIRST DONE" in terminal.text())
            terminal.until(lambda: "last turn" in status_line(terminal))
            terminal.repaint()
            line = status_line(terminal)
            print("after turn one:", line.strip())
            check("the status line says the turn's requests and tool calls", "last turn 2 requests, 1 tool" in line)
            check("and a time of at least a second, as a clock",
                  any(f"0:0{second}" in line for second in range(1, 10)))
            terminal.send(b"Again\r")
            time.sleep(1)
            terminal.repaint()
            check("while the next turn runs, the figure is gone", "last turn" not in status_line(terminal))
            server.hold.set()
            terminal.until(lambda: "SECOND DONE" in terminal.text())
            terminal.until(lambda: "last turn" in status_line(terminal))
            terminal.repaint()
            line = status_line(terminal)
            print("after turn two:", line.strip())
            check("then it says the new turn's, one request, no tool", "last turn 1 request ·" in line)
            terminal.send(b"Do the task\r")
            terminal.until(lambda: "THIRD DONE" in terminal.text())
            said = next((row for row in terminal.text().splitlines() if "t1 done:" in row), "")
            print("task done:", said.strip())
            check("a task made done says what it cost: two requests, two tools, a second or more",
                  "t1 done: 2 requests, 2 tools" in said and any(f"0:0{second}" in said for second in range(1, 10)))
            terminal.send(b"/tasks all\r")
            terminal.until(lambda: "[done] Read the notes ·" in terminal.text())
            row = next(row for row in terminal.text().splitlines() if "[done] Read the notes" in row)
            print("/tasks all:", row.strip())
            check("/tasks all says it after the task's line", "· 2 requests, 2 tools" in row)
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
