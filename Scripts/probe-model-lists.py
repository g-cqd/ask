#!/usr/bin/env python3
"""What the real binary does with a provider's model list, against a fake OpenAI-compatible server on this machine.

    python3 Scripts/probe-model-lists.py [.build/release/ask]

A: a run with no cached list sends no /models request and no window is known (the request's max_tokens is the default).
B: `ask models fake` lists the models with the limits the server states, caches them owner-only, and writes no key into the cache.
C: a run after that reads the cache, still sends no /models request, and sizes the reply to the window the list stated.
H: `ask models` always reads afresh. D: a damaged cache is said, and the run still works. E: a refused list names the status and not the body (exit 77 for 401).
F: a provider name that is not a plain word lists, but keeps no cache file. G: with no model named, the list is not used to pick one.
Nothing leaves the machine and no real credential is used.
"""
import http.server, json, os, pathlib, stat, subprocess, sys, tempfile, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
KEY = 'sk-probe-secret-value'
state = {'models': 0, 'chat': [], 'models_status': 200}
LIST = {'data': [{'id': 'org/m', 'context_length': 8000, 'top_provider': {'max_completion_tokens': 1000}},
                 {'id': 'plain'}, {'id': 'bad id'}]}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        state['models'] += 1
        state['auth'] = self.headers.get('authorization')
        if state['models_status'] != 200:
            body = ('rejected ' + KEY).encode()
            self.send_response(state['models_status'])
        else:
            body = json.dumps(LIST).encode()
            self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        state['chat'].append(json.loads(self.rfile.read(int(self.headers['content-length']))))
        chunks = [{'choices': [{'index': 0, 'delta': {'content': 'ok'}}]},
                  {'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}],
                   'usage': {'prompt_tokens': 1, 'completion_tokens': 1}}]
        payload = ''.join('data: %s\n\n' % json.dumps(c) for c in chunks) + 'data: [DONE]\n\n'
        self.send_response(200)
        self.send_header('content-type', 'text/event-stream')
        self.end_headers()
        self.wfile.write(payload.encode())

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-lists-probe-'))
config = root / 'config' / 'ask'
config.mkdir(parents=True, mode=0o700)
url = 'http://127.0.0.1:%d/v1' % server.server_address[1]
entry = {'api': 'openai-completions', 'baseUrl': url, 'apiKey': KEY}
(config / 'providers.json').write_text(json.dumps({'providers': {'fake': entry, 'Odd.Name': entry, '': entry}}))
env = {k: v for k, v in os.environ.items() if not k.startswith(('ANTHROPIC_', 'XDG_'))}
env |= {'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state')}
env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
cache = config / 'models-fake.json'


def ask(*args):
    p = subprocess.run([binary, *args], cwd=root, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


def run(model):
    state['chat'].clear()
    code, out, err = ask('--provider', 'fake', '--model', model, '--max-turns', '1', '--print', 'hi')
    assert code == 0, (code, out, err)
    body = state['chat'][-1]
    return body.get('max_tokens', body.get('max_completion_tokens')), err


before, err = run('org/m')
assert state['models'] == 0 and not cache.exists(), 'A: a run asked for the list, or wrote a cache'
print('PASS A  no cache: 0 /models requests, max_tokens=%s' % before)

code, out, err = ask('models', 'fake')
assert code == 0, (code, out, err)
assert state['models'] == 1 and state['auth'] == 'Bearer ' + KEY, state
assert 'org/m' in out and '8000' in out and '1000' in out and 'plain' in out and 'unknown' in out, out
assert 'bad id' not in out and '1 listed entries were left out' in err, (out, err)
assert 'No default' in out and '* ' not in out, out
mode = stat.S_IMODE(cache.stat().st_mode)
assert mode & 0o077 == 0, oct(mode)
assert KEY not in cache.read_text() and 'earer' not in cache.read_text()
print('PASS B  models fake: 1 request, limits shown, cache mode %s, no key in it' % oct(mode))

after, err = run('org/m')
assert state['models'] == 1, 'C: a run fetched the list'
assert after == 1000 and after != before, ('C: reply not sized by the list', before, after)
print('PASS C  max_tokens %s -> %s from the cached list, still 1 /models request' % (before, after))
plain, _ = run('plain')
assert plain == before, ('a model the list gives no limits keeps the default', plain, before)
print('PASS C2 a listed model with no limits keeps the default max_tokens (%s)' % plain)

LIST['data'].append({'id': 'newer'})
code, out, err = ask('models', 'fake')
assert code == 0 and 'newer' in out and state['models'] == 2, ('H: `ask models` did not read the list afresh', out)
print('PASS H  `ask models` refreshes a fresh cache')
cache.write_text('not json')
again, err = run('org/m')
assert 'Model list not used' in err and again == before, (err, again)
print('PASS D  damaged cache: said, run unaffected')
cache.unlink()

state['models_status'] = 401
code, out, err = ask('models', 'fake')
assert code == 77 and '401' in err and KEY not in err + out and 'rejected' not in err + out, (code, out, err)
state['models_status'] = 500
code, out, err = ask('models', 'fake')
assert code == 69 and '500' in err and KEY not in err + out, (code, out, err)
assert not cache.exists(), 'a refusal wrote a cache'
print('PASS E  refusal: 401 exits 77, 500 exits 69, status named, body and key not shown, no cache')
state['models_status'] = 200

before_files = sorted(p.name for p in config.iterdir())
code, out, err = ask('models', 'Odd.Name')
assert code == 0 and 'org/m' in out, (code, out, err)
assert sorted(p.name for p in config.iterdir()) == before_files, 'F: a name that is not a plain word wrote a file'
code, out, err = ask('models', '')
assert code == 0 and 'org/m' in out, (code, out, err)
assert sorted(p.name for p in config.iterdir()) == before_files, 'F: an empty provider name wrote a file'
print('PASS F  providers "Odd.Name" and "" list and keep no cache file')

n = state['models']
code, out, err = ask('--provider', 'fake', '--max-turns', '1', '--print', 'hi')
assert code == 78 and 'lists no model' in err and state['models'] == n, (code, err)
print('PASS G  no model named: exit 78, nothing chosen from the list, no request')
print('ROOT', root)
