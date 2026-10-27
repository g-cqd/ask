#!/usr/bin/env python3
"""Measure prompt startup with/without a 468-model cache, alternating order.

    python3 Scripts/measure-model-cache.py [.build/release/ask] [12]

Uses the real release binary and a local fake /models server to write the cache. No real key or external request. The
synthetic list has the size of the OpenRouter catalog observed on 2026-10-20, not a claim about any live model. The cached
and uncached cases use identical provider/model selection. Rebuild with `swift build -c release` first: tests may replace
.build/release/ask with a testable binary. Reports median, p95 and range, never best-run performance.
"""
import fcntl
import http.server
import json
import math
import os
import pathlib
import pty
import select
import signal
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

BINARY = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 12
if RUNS < 2:
    raise SystemExit('at least two samples per case are needed')
MODEL = 'probe/model-467'
BODY = json.dumps({'data': [
    {'id': 'probe/model-%03d' % i, 'context_length': 131072, 'top_provider': {'max_completion_tokens': 16384}}
    for i in range(468)
]}).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass


def sample(config, state, cwd):
    started = time.monotonic()
    pid, fd = pty.fork()
    if pid == 0:
        # Set the size before exec: changing it from the parent races ask's first terminal-size read.
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        os.environ.update(TERM='xterm-kitty', TERM_PROGRAM='kitty', XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state))
        os.chdir(cwd)
        os.execv(BINARY, [BINARY, '--provider', 'probe', '--model', MODEL])
        os._exit(127)
    try:
        deadline = started + 10
        output = b''
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            if "────".encode() in output:
                return (time.monotonic() - started) * 1000
        raise RuntimeError('no prompt within 10 s; incomplete sample, not a latency; tail=%r' % output[-400:])
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(fd)


def main():
    with tempfile.TemporaryDirectory(prefix='ask-cache-budget-') as directory:
        root = pathlib.Path(directory)
        config = root / 'config'
        home = config / 'ask'
        home.mkdir(parents=True)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            (home / 'providers.json').write_text(json.dumps({'providers': {'probe': {
                'api': 'openai-completions', 'baseUrl': 'http://127.0.0.1:%d/v1' % server.server_address[1]}}}))
            env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(root / 'state'))
            listed = subprocess.run([BINARY, 'models', 'probe'], cwd=root, env=env, capture_output=True, timeout=30)
            if listed.returncode:
                raise RuntimeError(listed.stderr.decode(errors='replace'))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        file = home / 'models-probe.json'
        hidden = home / 'models-probe.hidden'
        print('binary %d B; cache %d B, 468 synthetic models, selected last entry' % (os.stat(BINARY).st_size, file.stat().st_size))
        samples = {'cache': [], 'no-cache': []}
        for index in range(RUNS):
            for case in (['cache', 'no-cache'] if index % 2 == 0 else ['no-cache', 'cache']):
                if case == 'no-cache' and file.exists():
                    file.rename(hidden)
                if case == 'cache' and hidden.exists():
                    hidden.rename(file)
                value = sample(config, root / 'state', root)
                samples[case].append(value)
                print('%s %d: %.3f ms' % (case, index + 1, value), flush=True)
        for case, values in samples.items():
            values.sort()
            print('%s n=%d p50=%.3f p95=%.3f range=%.3f..%.3f ms' % (
                case, len(values), statistics.median(values), values[math.ceil(0.95 * len(values)) - 1], values[0], values[-1]))


if __name__ == '__main__':
    main()
