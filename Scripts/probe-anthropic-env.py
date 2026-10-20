#!/usr/bin/env python3
"""What the real binary sends for each Anthropic environment variable, against a fake server on this machine.

    python3 Scripts/probe-anthropic-env.py [.build/release/ask]

A local server records the headers of every request and answers 401, so nothing leaves the machine and no real credential is
used: ANTHROPIC_BASE_URL points at 127.0.0.1, which ask accepts over plain http. It checks the order of the variables, the headers
each one produces, that an empty variable does not mask a valid one, and that a variable that is not a plain token stops the run
before any request is made. Prints one PASS line per case and stops at the first failure.
"""
import http.server, json, os, pathlib, subprocess, sys, tempfile, threading

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('content-length', 0)))
        requests.append({k.lower(): v for k, v in self.headers.items()} | {'_path': self.path})
        body = json.dumps({'type': 'error', 'error': {'type': 'authentication_error', 'message': 'fake'}}).encode()
        self.send_response(401)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-anthropic-env-'))
base = {k: v for k, v in os.environ.items() if not k.startswith('ANTHROPIC_')}
base |= {'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state'),
         'ANTHROPIC_BASE_URL': 'http://127.0.0.1:%d' % server.server_address[1]}


def run(name, variables, expect_request, check=None, exit_code=None):
    before = len(requests)
    p = subprocess.run([binary, '--provider', 'anthropic', '--model', 'claude-x', '--max-turns', '1', '--print', 'hi'],
                       cwd=root, env=base | variables, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=40)
    seen = requests[before:]
    output = p.stdout + p.stderr
    if expect_request:
        assert seen, (name, 'no request reached the server', output)
        headers = seen[0]
        assert headers['_path'] == '/v1/messages', (name, headers['_path'])
        if check:
            assert check(headers), (name, headers)
    else:
        assert not seen, (name, 'a request was sent', seen)
        assert p.returncode == exit_code, (name, p.returncode, output)
    for secret in [v for v in variables.values() if len(v) > 6 and v.isascii() and v.isprintable()]:
        assert secret not in output, (name, 'a credential reached the output')
    print('PASS', name.ljust(66), 'requests=%d' % len(seen), 'exit=%d' % p.returncode, flush=True)
    return output


run('only ANTHROPIC_AUTH_TOKEN: a bearer, no key, no subscription beta', {'ANTHROPIC_AUTH_TOKEN': 'gateway-token-1'}, True,
    lambda h: h['authorization'] == 'Bearer gateway-token-1' and 'x-api-key' not in h and 'anthropic-beta' not in h)
run('only ANTHROPIC_OAUTH_TOKEN: a bearer with the subscription beta', {'ANTHROPIC_OAUTH_TOKEN': 'sk-ant-oat-fake1'}, True,
    lambda h: h['authorization'] == 'Bearer sk-ant-oat-fake1' and 'oauth' in h.get('anthropic-beta', ''))
run('only ANTHROPIC_API_KEY: x-api-key and no Authorization', {'ANTHROPIC_API_KEY': 'sk-ant-api-fake1'}, True,
    lambda h: h['x-api-key'] == 'sk-ant-api-fake1' and 'authorization' not in h)
run('all three set: the auth token wins', {'ANTHROPIC_AUTH_TOKEN': 'gateway-token-2', 'ANTHROPIC_OAUTH_TOKEN': 'sk-ant-oat-fake2',
    'ANTHROPIC_API_KEY': 'sk-ant-api-fake2'}, True,
    lambda h: h['authorization'] == 'Bearer gateway-token-2' and 'x-api-key' not in h)
run('oauth and key set: the oauth token wins', {'ANTHROPIC_OAUTH_TOKEN': 'sk-ant-oat-fake3', 'ANTHROPIC_API_KEY': 'sk-ant-api-fake3'},
    True, lambda h: h['authorization'] == 'Bearer sk-ant-oat-fake3' and 'x-api-key' not in h)
run('an empty auth token does not mask a valid key', {'ANTHROPIC_AUTH_TOKEN': '', 'ANTHROPIC_API_KEY': 'sk-ant-api-fake4'}, True,
    lambda h: h['x-api-key'] == 'sk-ant-api-fake4')
for label, bad in [('a space', 'bad token'), ('a newline', 'bad\nX-Injected: 1'), ('a carriage return', 'bad\rtoken'),
                   ('a non-ASCII letter', 'tokén-fake')]:
    out = run('an auth token with %s stops the run before any request' % label,
              {'ANTHROPIC_AUTH_TOKEN': bad, 'ANTHROPIC_API_KEY': 'sk-ant-api-never-used'}, False, exit_code=77)
    assert 'ANTHROPIC_AUTH_TOKEN is not a plain token' in out, out
    assert 'sk-ant-api-never-used' not in out
print('ROOT', root)
