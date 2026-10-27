#!/usr/bin/env python3
"""Measure prompt startup for an explicit Claude thinking level: unset, warm metadata cache, and cache miss.

    python3 Scripts/measure-thinking-start.py [.build/release/ask] [12]

Uses the real release binary and a local fake Anthropic server; no real credential or external request. The miss case
defers its metadata lookup to the first request (ADR-0059), so no startup request is made; the script asserts that by
requiring the cache to still be absent after the sample. Cases are interleaved so background load cancels. Reports median, p95 and range, never the best run. Rebuild with
`swift build -c release` first: tests may replace .build/release/ask with a testable binary.
"""
import fcntl, http.server, json, math, os, pathlib, pty, select, signal, statistics, struct, subprocess, sys, tempfile, termios, threading, time

BINARY = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 12
if RUNS < 2:
    raise SystemExit('at least two samples per case are needed')
MODELS = json.dumps({'data': [
    {'id': 'model-%02d' % i, 'max_input_tokens': 200000, 'max_tokens': 64000,
     'capabilities': {'thinking': {'supported': True, 'types': {'adaptive': {'supported': True}, 'between_tools': {'supported': True}}},
                      'effort': {name: {'supported': True} for name in ['low', 'medium', 'high', 'xhigh', 'max']}}}
    for i in range(14)], 'has_more': False, 'last_id': 'model-13'}).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(MODELS)))
        self.end_headers()
        self.wfile.write(MODELS)

    def log_message(self, *args):
        pass


def sample(config, state, cwd, base, flags):
    started = time.monotonic()
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        env = {k: v for k, v in os.environ.items() if not k.startswith(('ANTHROPIC_', 'ASK_'))}
        env.update(TERM='xterm-kitty', TERM_PROGRAM='kitty', XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state),
                   ANTHROPIC_BASE_URL=base, ANTHROPIC_API_KEY='fixture-start-key')
        os.chdir(cwd)
        os.execve(BINARY, [BINARY, '--provider', 'anthropic', '--model', 'model-07'] + flags, env)
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
        raise RuntimeError('no prompt within 10 s; incomplete sample; tail=%r' % output[-400:])
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(fd)


def nearest_rank(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def main():
    with tempfile.TemporaryDirectory(prefix='ask-thinking-start-') as directory:
        root = pathlib.Path(directory)
        config, state = root / 'config', root / 'state'
        (config / 'ask').mkdir(parents=True)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = 'http://127.0.0.1:%d' % server.server_address[1]
        try:
            cache = config / 'ask' / 'models-anthropic.json'
            hidden = config / 'ask' / 'models-anthropic.hidden'
            listed = subprocess.run([BINARY, 'models', 'anthropic'], cwd=root, capture_output=True, timeout=30, env={
                **os.environ, 'XDG_CONFIG_HOME': str(config), 'XDG_STATE_HOME': str(state), 'ANTHROPIC_BASE_URL': base,
                'ANTHROPIC_API_KEY': 'fixture-start-key'})
            assert listed.returncode == 0 and cache.exists(), listed.stderr.decode(errors='replace')
            print('binary %d B; cache %d B, 14 synthetic models' % (os.stat(BINARY).st_size, cache.stat().st_size))
            cases = {'unset': [], 'warm cache': [], 'cache miss (deferred)': []}
            flags = {'unset': [], 'warm cache': ['--thinking', 'high'], 'cache miss (deferred)': ['--thinking', 'high']}
            order = list(cases)
            for index in range(RUNS):
                for case in (order if index % 2 == 0 else order[::-1]):
                    if case == 'cache miss (deferred)' and cache.exists():
                        cache.rename(hidden)
                    elif case != 'cache miss (deferred)' and hidden.exists():
                        hidden.rename(cache)
                    value = sample(config, state, root, base, flags[case])
                    if case == 'cache miss (deferred)':
                        assert not cache.exists(), 'startup fetched the metadata, so the lookup was not deferred'
                    cases[case].append(value)
                    print('%s %d: %.3f ms' % (case, index + 1, value), flush=True)
        finally:
            server.shutdown()
            server.server_close()
        for case, values in cases.items():
            print('%-24s median %.3f ms  p95 %.3f  min %.3f  max %.3f  (n=%d)' % (
                case, statistics.median(values), nearest_rank(values, 0.95), min(values), max(values), len(values)))


main()
