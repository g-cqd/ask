#!/usr/bin/env python3
"""Check that a dropped connection is said by the status bar, not by a block, through the real binary, a PTY and a provider that fails first.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-reconnecting.py .build/release/ask

The provider answers 529 (overloaded) with retry-after 2 s, then the answer. While ask waits, the status bar must start with the spinner and
"Reconnecting..."; the conversation must hold no message about it; after the answer the usual mark is back. pyte, not a physical terminal.
"""
import importlib.util
import json
import socket
import time
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


class DroppingMidAnswer:
    """A provider whose first answer streams some text and then loses the connection (chunked, never finished); then `answer`."""

    def __init__(self, first_text, answer):
        self.first_text, self.answer, self.requests = first_text, answer, []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def do_POST(self):
                outer.requests.append(json.loads(self.rfile.read(int(self.headers["content-length"]))))
                if len(outer.requests) == 1:
                    events = [{"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}},
                              {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
                              {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": outer.first_text}}]
                    body = agent.sse(events)
                    self.send_response(200)
                    self.send_header("content-type", "text/event-stream")
                    self.send_header("transfer-encoding", "chunked")
                    self.end_headers()
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(body), body))
                    self.wfile.flush()
                    time.sleep(0.5)
                    # The connection is lost: no last chunk, the socket just closes.
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    return
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("content-length", str(len(outer.answer)))
                self.end_headers()
                self.wfile.write(outer.answer)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def dropped_mid_answer():
    """An answer cut part way is carried on (roadmap 0141): what was shown stays, the model is asked to continue, no error block."""
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","separator":"off"}}')
        server = DroppingMidAnswer("FIRST HALF", agent.turn([("text", " SECOND HALF")], "end_turn"))
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"Go\r")
            terminal.until(lambda: "SECOND HALF" in terminal.text())
            terminal.repaint()
            text = terminal.text()
            check("the part shown before the drop stays, and the rest follows", "FIRST HALF" in text and "SECOND HALF" in text)
            check("no error block says the connection was lost", "ask:" not in text and "connection" not in text.lower())
            sent = server.requests[1]["messages"][-2:] if len(server.requests) > 1 else []
            check("the model was sent what it had written, then asked to carry on",
                  len(sent) == 2 and sent[0]["role"] == "assistant" and "FIRST HALF" in json.dumps(sent[0]["content"])
                  and sent[1]["role"] == "user" and "connection dropped" in json.dumps(sent[1]["content"]))
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","separator":"off"}}')
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
    dropped_mid_answer()
