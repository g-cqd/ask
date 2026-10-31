#!/usr/bin/env python3
"""What the real binary does with a provider's usage limit, against a fake server on this machine.

    python3 Scripts/probe-quota.py [.build/release/ask]

The server answers 429 with the body ChatGPT's backend really sent when an account was over its plan (recorded in
Tests/Fixtures/Codex/usage-limit-429.json). A usage limit lifts at a set time, so ask must not retry it and must say when it
lifts. The control answers an ordinary rate limit, which must still be retried. Nothing leaves the machine and no credential is used.
"""
import http.server, json, os, pathlib, subprocess, sys, tempfile, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

here = pathlib.Path(__file__).resolve().parent.parent
binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
usage_body = (here / 'Tests/Fixtures/Codex/usage-limit-429.json').read_bytes()
rate_body = json.dumps({'error': {'type': 'rate_limit_exceeded', 'message': 'Slow down'}}).encode()
mode = {'value': 'usage'}
count = [0]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('content-length', 0)))
        count[0] += 1
        body = usage_body if mode['value'] == 'usage' else rate_body
        self.send_response(429)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body)))
        if mode['value'] == 'rate':
            self.send_header('retry-after', '0')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-quota-probe-'))
config = root / 'config' / 'ask'
config.mkdir(parents=True, mode=0o700)
(config / 'providers.json').write_text(json.dumps({'providers': {'fake': {
    'api': 'openai-responses', 'baseUrl': 'http://127.0.0.1:%d/v1' % server.server_address[1], 'models': [{'id': 'm'}]}}}))
env = {k: v for k, v in os.environ.items() if not k.startswith('ANTHROPIC_')}
env |= {'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state')}
env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain


def run(which):
    mode['value'] = which
    count[0] = 0
    started = time.time()
    p = subprocess.run([binary, '--provider', 'fake', '--max-turns', '1', '--print', 'hi'], cwd=root, env=env,
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    return count[0], p.returncode, p.stdout + p.stderr, time.time() - started


requests, code, out, seconds = run('usage')
assert requests == 1, ('a usage limit was retried', requests, out)
assert code == 69, (code, out)
assert 'The usage limit has been reached; it resets in about 20 minutes' in out, out
assert 'retrying' not in out, out
print('PASS usage limit  requests=%d exit=%d in %.1fs: %s' % (requests, code, seconds,
      [l for l in out.splitlines() if 'usage limit' in l][-1].strip()))

requests, code, out, seconds = run('rate')
assert requests > 1, ('an ordinary rate limit was not retried', requests, out)
assert 'retrying' in out and 'Slow down' in out, out
print('PASS rate limit   requests=%d exit=%d in %.1fs (still retried)' % (requests, code, seconds))
print('ROOT', root)
