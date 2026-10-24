#!/usr/bin/env python3
"""Probe the held view and the "N lines below" count (ADR-0072) through the real binary, a PTY and a gated fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-lines-below.py .build/release/ask [--control OLDER_BINARY]

The provider streams a reply in two parts and holds the second until the probe has scrolled back, so the reader is looking at
something while more text arrives below it. With --control, a binary that predates the change must let the screen slide: a probe that
cannot fail is not a probe.
"""
import importlib.util
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
sys.argv = saved
agent = pp.probe.agent
check, press, rows = pp.check, pp.press, pp.rows


def part(events):
    return agent.sse(events)


def reply(first, second):
    """A reply in two writes: the first now, the second when `release` is set."""
    head = [{"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}},
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": first}}]
    tail = [{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": second}},
            {"type": "content_block_stop", "index": 0},
            {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 5}},
            {"type": "message_stop"}]
    return part(head), part(tail)


class GatedServer:
    """Serves one two-part reply, holding the second part until `release` is set."""

    def __init__(self, responses):
        self.requests, self.release = [], threading.Event()
        outer = self
        first, second = reply("\n".join(f"EARLY {n}" for n in range(1, 41)), "\n" + "\n".join(f"LATE {n}" for n in range(1, 21)))

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                outer.requests.append({"body": body, "headers": {k.lower(): v for k, v in self.headers.items()}})
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.end_headers()
                self.wfile.write(first)
                self.wfile.flush()
                outer.release.wait(30)
                self.wfile.write(second)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def status_row(terminal):
    return next((i for i, line in enumerate(rows(terminal)) if " · ready" in line or "working…" in line), None)


def transcript(terminal):
    """The transcript rows, above the status line."""
    return rows(terminal)[:status_row(terminal)]


def wheel_up(terminal, times):
    for _ in range(times):
        press(terminal, b"\x1b[<64;10;3M")


def scenario(binary, label, expect_hold):
    gated = GatedServer([])
    original, agent.Server = agent.Server, lambda turns: gated
    try:
        with pp.Session(binary, []) as session:
            terminal = session.terminal
            pp.type_text(terminal, "stream")
            press(terminal, b"\r")
            terminal.until(lambda: "EARLY 40" in terminal.text())
            terminal.repaint()
            wheel_up(terminal, 2)
            terminal.repaint()
            before = transcript(terminal)
            line = rows(terminal)[status_row(terminal)]
            shown = "lines below" in line
            counted = int(line.split("lines below")[0].split()[-1]) if shown else None
            check(f"{label}: scrolled back, the reader sees early lines, not the end", "EARLY 40" not in "\n".join(before))
            gated.release.set()
            for _ in range(40):
                terminal.pump()
                if " · ready" in "\n".join(rows(terminal)) and "working" not in "\n".join(rows(terminal)):
                    break
            terminal.repaint()
            after = transcript(terminal)
            held = after == before
            check(f"{label}: the view {'stays on what was being read' if expect_hold else 'slides (the control)'} while the rest arrives",
                  held == expect_hold)
            line = rows(terminal)[status_row(terminal)]
            if expect_hold:
                now = int(line.split("lines below")[0].split()[-1]) if "lines below" in line else None
                check("the count grew by exactly the twenty late lines", shown and now == counted + 20)
                press(terminal, b"\x1b[F")  # End, with nothing in the draft
                terminal.repaint()
                check("End on an empty draft goes to the end", any("LATE 20" in text for text in rows(terminal))
                      and "lines below" not in rows(terminal)[status_row(terminal)])
                wheel_up(terminal, 3)
                terminal.repaint()
                line = rows(terminal)[status_row(terminal)]
                column = line.index("lines below") + 2
                press(terminal, f"\x1b[<0;{column + 1};{status_row(terminal) + 1}M".encode())
                press(terminal, f"\x1b[<0;{column + 1};{status_row(terminal) + 1}m".encode())
                terminal.repaint()
                check("a click on the count goes to the end", any("LATE 20" in text for text in rows(terminal))
                      and "lines below" not in rows(terminal)[status_row(terminal)])
            else:
                check("control: an older binary shows no count", "lines below" not in line and not shown)
    finally:
        agent.Server = original
        gated.httpd.shutdown()
        gated.httpd.server_close()


def main():
    binary = os.path.abspath(sys.argv[1])
    if "--control" in sys.argv:
        scenario(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]), "control", expect_hold=False)
    scenario(binary, "candidate", expect_hold=True)
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
