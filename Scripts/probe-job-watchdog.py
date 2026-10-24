#!/usr/bin/env python3
"""Probe the job watchdog (ADR-0077) through the real binary: a job must not outlive an ask that is killed with SIGKILL.

Scripts/probe-job-watchdog.py .build/release/ask [--control OLDER_BINARY]

`ask -p` starts a job, the fake provider holds its next answer so ask is in the middle of the run, the probe sends SIGKILL to ask, and
looks at the job's own process. With --control, a binary that predates the watchdog must leave the job running: a probe that cannot
fail is not a probe. Every process the probe started is stopped at the end, whatever happened.
"""
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
sys.argv = saved
checks = []


def check(label, condition):
    print(("PASS " if condition else "FAIL ") + label, flush=True)
    checks.append(label)
    if not condition:
        raise AssertionError(label)


class HoldingServer:
    """Answers the first request with a tool call that starts a job, then holds every later request until released."""

    def __init__(self, command):
        self.requests, self.release = [], threading.Event()
        first = agent.turn([("call", "t1", "bash", {"command": command, "yield_seconds": 1})], "tool_use")
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                outer.requests.append(body)
                if len(outer.requests) > 1:
                    outer.release.wait(60)
                try:
                    self.send_response(200)
                    self.send_header("content-type", "text/event-stream")
                    self.end_headers()
                    self.wfile.write(first if len(outer.requests) == 1 else agent.turn([("text", "done")], "end_turn"))
                except (BrokenPipeError, ConnectionResetError):
                    pass  # ask was killed while its request was held, which is the point

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def wait_for(condition, seconds):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.05)
    return condition()


def scenario(binary, label, expect_stopped):
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = HoldingServer("sleep 300 & echo $! > child.pid; wait")
    ask = subprocess.Popen([binary, "-p", "Start a job."], cwd=project, env=agent.environment(state, server.url),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    child = None
    try:
        pidfile = os.path.join(project, "child.pid")
        check(f"{label}: the job started and ask is mid-run",
              wait_for(lambda: len(server.requests) >= 2 and os.path.exists(pidfile) and open(pidfile).read().strip(), 30))
        child = int(open(pidfile).read())
        check(f"{label}: the job is running", alive(child))
        ask.send_signal(signal.SIGKILL)
        ask.wait()
        check(f"{label}: ask died by SIGKILL", ask.returncode == -signal.SIGKILL)
        if expect_stopped:
            check(f"{label}: the job is stopped within a moment of ask's death", wait_for(lambda: not alive(child), 6))
        else:
            time.sleep(3)
            check(f"{label}: the job outlives ask (the failure the watchdog is for)", alive(child))
    finally:
        if child is not None:
            try:
                os.killpg(os.getpgid(child), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                os.kill(child, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if ask.poll() is None:
            ask.kill()
        server.release.set()
        server.httpd.shutdown()
        server.httpd.server_close()


def main():
    binary = os.path.abspath(sys.argv[1])
    if "--control" in sys.argv:
        scenario(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]), "control", expect_stopped=False)
    scenario(binary, "candidate", expect_stopped=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
