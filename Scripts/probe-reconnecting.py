#!/usr/bin/env python3
"""Check that a dropped connection is said by the status bar, not by a block, through the real binary, a PTY and a provider that fails first.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-reconnecting.py .build/release/ask

The provider answers 529 (overloaded) with retry-after 2 s, then the answer. While ask waits, the status bar must start with the spinner and
"Reconnecting..."; the conversation must hold no message about it; after the answer the usual mark is back. pyte, not a physical terminal.
"""
import importlib.util
import json
import os
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check


class FailingFirst:
    """A provider that answers 529 `failures` times, then streams `answer`."""

    def __init__(self, failures, answer):
        self.failures, self.answer = failures, answer
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers["content-length"]))
                if outer.failures > 0:
                    outer.failures -= 1
                    body = json.dumps({"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}})
                    self.send_response(529)
                    self.send_header("content-type", "application/json")
                    self.send_header("retry-after", "2")
                    self.end_headers()
                    self.wfile.write(body.encode())
                    return
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.end_headers()
                self.wfile.write(outer.answer)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"prompt":"ask> ","separator":"off"}}')
        server = FailingFirst(1, agent.turn([("text", "PROBE ANSWER")], "end_turn"))
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Go\r")
            terminal.until(lambda: "Reconnecting..." in terminal.text())
            status = next(line for line in terminal.screen.display if "Reconnecting..." in line)
            check("while ask waits, the status bar starts with the spinner and Reconnecting...",
                  status.lstrip()[1:].startswith(" Reconnecting... · "))
            check("no block in the conversation says the connection dropped",
                  not any(word in terminal.text() for word in ("retrying", "Overloaded", "overloaded", "attempt")))
            terminal.until(lambda: "PROBE ANSWER" in terminal.text())
            terminal.repaint()
            check("once the answer comes the usual mark is back", "Reconnecting..." not in terminal.text())
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
