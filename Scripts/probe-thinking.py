#!/usr/bin/env python3
"""The shipped CLI's thinking controls against local native/Responses fakes. No real token or network is used.

    python3 Scripts/probe-thinking.py [.build/release/ask]

Checks outgoing bytes, precedence/reset, model-specific off, legacy budgets, metadata authorization changes,
explicit refresh/refusal, offline reports and propagation through a real read-tool turn. Synthetic acceptance is
not a live provider guarantee. The Swift suites independently exercise damaged optional fields and pagination.
"""
import http.server
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.parse

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
KEY = 'fixture-native-key-one'
lock = threading.Lock()
state = {'get': [], 'post': [], 'status': 200, 'tool': False, 'paging': False}
levels = {name: {'supported': name != 'minimal'} for name in ['minimal', 'low', 'medium', 'high', 'xhigh', 'max']}


def model(name, modes, efforts=None):
    return {'id': name, 'max_input_tokens': 64000, 'max_tokens': 32000,
            'capabilities': {'thinking': {'supported': True, 'types': {m: {'supported': True} for m in modes}},
                             'effort': efforts or {}}}


models = [model('modern', ['adaptive', 'between_tools'], levels), model('old', ['enabled', 'disabled']),
          model('disabled-mode', ['adaptive', 'disabled'], levels), model('always', ['adaptive'], levels)]


def sse(events):
    return ''.join('event: %s\ndata: %s\n\n' % (name, json.dumps(data)) for name, data in events).encode()


def native_reply(tool):
    kind = 'tool_use' if tool else 'text'
    block = {'type': kind, 'id': 't', 'name': 'read', 'input': {}} if tool else {'type': 'text', 'text': ''}
    delta = {'type': 'input_json_delta', 'partial_json': json.dumps({'path': 'input.txt'})} if tool else {'type': 'text_delta', 'text': 'THINKING_OK'}
    return sse([
        ('message_start', {'type': 'message_start', 'message': {'id': 'm', 'role': 'assistant', 'model': 'modern', 'content': [], 'usage': {'input_tokens': 1, 'output_tokens': 0}}}),
        ('content_block_start', {'type': 'content_block_start', 'index': 0, 'content_block': block}),
        ('content_block_delta', {'type': 'content_block_delta', 'index': 0, 'delta': delta}),
        ('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
        ('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': 'tool_use' if tool else 'end_turn'}, 'usage': {'output_tokens': 1}}),
        ('message_stop', {'type': 'message_stop'})])


def responses_reply():
    item = {'id': 'msg', 'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'THINKING_OK'}]}
    return sse([
        ('response.created', {'type': 'response.created', 'response': {'id': 'r', 'model': 'm'}}),
        ('response.output_item.added', {'type': 'response.output_item.added', 'item': item | {'content': []}}),
        ('response.output_text.delta', {'type': 'response.output_text.delta', 'item_id': 'msg', 'delta': 'THINKING_OK'}),
        ('response.output_item.done', {'type': 'response.output_item.done', 'item': item}),
        ('response.completed', {'type': 'response.completed', 'response': {'id': 'r', 'model': 'm', 'status': 'completed', 'usage': {'input_tokens': 1, 'output_tokens': 1}}})])


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, status, payload, kind='application/json'):
        self.send_response(status)
        self.send_header('content-type', kind)
        self.send_header('content-length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        with lock:
            state['get'].append((self.path, self.headers.get('x-api-key')))
            status, paging = state['status'], state['paging']
        if status != 200:
            return self.reply(status, ('refusal-body-' + KEY).encode())
        page = models
        more = False
        if paging:
            page = models[2:] if query.get('after_id') == ['old'] else models[:2]
            more = page == models[:2]
        self.reply(200, json.dumps({'data': page, 'has_more': more, 'last_id': page[-1]['id']}).encode())

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['content-length'])))
        with lock:
            state['post'].append((self.path, body))
            tool = state['tool']
        has_result = any(b.get('type') == 'tool_result' for m in body.get('messages', []) for b in m.get('content', []) if isinstance(b, dict))
        self.reply(200, responses_reply() if self.path.endswith('/responses') else native_reply(tool and not has_result), 'text/event-stream')

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-thinking-probe-'))
config = root / 'config' / 'ask'
config.mkdir(parents=True, mode=0o700)
(root / 'input.txt').write_text('LOCAL_TOOL_RESULT')
base = 'http://127.0.0.1:%d' % server.server_address[1]
env = {k: v for k, v in os.environ.items() if not k.startswith(('ANTHROPIC_', 'ASK_', 'XDG_'))}
env |= {'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state'),
        'ANTHROPIC_BASE_URL': base, 'ANTHROPIC_API_KEY': KEY}
(config / 'providers.json').write_text(json.dumps({'providers': {
    'responses': {'api': 'openai-responses', 'baseUrl': base + '/v1', 'apiKey': 'fixture-responses-key'},
    'chat': {'api': 'openai-completions', 'baseUrl': base + '/v1', 'apiKey': 'fixture-chat-key'}}}))
cache = config / 'models-anthropic.json'
checks = 0
EXPECT_LATE = 69


def ask(*args, variables=None, expect=0):
    result = subprocess.run([binary, *args], cwd=root, env=env | (variables or {}), stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, timeout=40)
    assert result.returncode == expect, (args, result.returncode, result.stdout, result.stderr)
    assert KEY not in result.stdout + result.stderr
    return result


def run(*flags, model='modern', variables=None, expect=0, provider='anthropic'):
    return ask('--provider', provider, '--model', model, '--max-turns', '4', '--print', 'hello', *flags,
               variables=variables, expect=expect)


def counts():
    with lock:
        return len(state['get']), len(state['post'])


def body():
    with lock:
        return state['post'][-1][1]


def passed(name):
    global checks
    checks += 1
    print('PASS', name, flush=True)


run()
assert counts() == (0, 1) and 'thinking' not in body() and 'output_config' not in body() and not cache.exists()
passed('unset: no metadata request or new wire fields')
before = counts()
result = ask('config', variables={'ASK_THINKING': 'high'})
assert counts() == before and 'will be looked up before the first request' in result.stdout and not cache.exists()
passed('cold cache: loading settings makes no network request and says the level is pending')
run('--thinking', 'high')
assert counts() == (1, 2) and body()['thinking'] == {'type': 'adaptive'} and body()['output_config'] == {'effort': 'high'}
assert body()['max_tokens'] == 16384, 'a deferred lookup cannot have sized this request from the model limits'
assert stat.S_IMODE(cache.stat().st_mode) == 0o600 and KEY not in cache.read_text()
passed('native high, cold: looked up at the first request, exact effort, owner-only token-free cache')
run('--thinking', 'high')
assert counts() == (1, 3) and body()['output_config'] == {'effort': 'high'} and body()['max_tokens'] == 16000
passed('native high, warm: no lookup, and the request is sized from the cached limits')
(config / 'config.json').write_text(json.dumps({'provider': 'anthropic', 'model': 'modern', 'thinking': 'high'}))
run(variables={'ASK_THINKING': 'low'})
assert body()['output_config']['effort'] == 'low' and counts()[0] == 1
passed('environment overrides the file without another catalog request')
run('--thinking', 'default', variables={'ASK_THINKING': 'low'})
assert 'thinking' not in body() and 'output_config' not in body() and counts()[0] == 1
passed('explicit default resets file and environment without new controls')
result = run(variables={'ASK_THINKING': 'invalid'})
assert body()['output_config']['effort'] == 'high' and '$ASK_THINKING' in result.stderr and 'ignored' in result.stderr
passed('invalid environment is reported, not silently used')
run('--thinking', 'off')
assert body()['thinking'] == {'type': 'between_tools'} and 'output_config' not in body()
run('--thinking', 'off', model='disabled-mode')
assert body()['thinking'] == {'type': 'disabled'}
passed('off follows each model metadata: between_tools versus disabled')
run('--thinking', 'minimal', model='old')
assert body()['thinking'] == {'type': 'enabled', 'budget_tokens': 1024} and 'output_config' not in body()
passed('legacy minimal: concrete 1024-token budget, no invented effort')
before = counts()
run('--thinking', 'minimal', expect=78)
run('--thinking', 'off', model='always', expect=78)
assert counts() == before
passed('unsupported effort or off is refused before inference, not clamped')
cache.unlink()
before = counts()
result = run('--thinking', 'minimal', expect=EXPECT_LATE)
assert counts() == (before[0] + 1, before[1]), 'a refusal after the lookup must not reach inference'
assert 'minimal is unavailable for modern' in result.stdout + result.stderr, (result.stdout, result.stderr)
passed('cold cache: a level the model lacks is refused after the lookup, before inference')
before = counts()
run('--thinking', 'low', variables={'ANTHROPIC_API_KEY': 'fixture-native-key-two'})
assert counts()[0] == before[0] + 1 and 'fixture-native-key-two' not in cache.read_text()
passed('authorization replacement invalidates the old descriptor scope')
before = counts()
run('--thinking', 'high', variables={'ANTHROPIC_API_KEY': ''}, expect=77)
assert counts() == before
passed('sign-out cannot reuse another authorization scope or make a model request')
# Restore one current-key catalog, then verify forced refresh and page cursors through the real URL builder.
with lock:
    state['paging'] = True
before = counts()
result = ask('models', 'anthropic')
assert counts()[0] == before[0] + 2 and 'THINKING MODES' in result.stdout and 'between_tools' in result.stdout
assert '64000' in result.stdout and '32000' in result.stdout and 'old' in result.stdout
with lock:
    assert 'after_id=old' in state['get'][-1][0] and 'limit=1000' in state['get'][-1][0]
    state['paging'] = False
passed('explicit listing refreshes, paginates, and displays modes and limits')
old = cache.read_bytes()
with lock:
    state['status'] = 401
result = ask('models', 'anthropic', expect=77)
assert '401' in result.stderr and 'refusal-body' not in result.stdout + result.stderr and cache.read_bytes() == old
with lock:
    state['status'] = 200
passed('native catalog refusal is status-only, exit 77, old cache unchanged')
before = counts()
result = ask('config')
assert counts() == before and 'thinking' in result.stdout and 'high (catalog-selected:' in result.stdout
assert str(config / 'config.json') in result.stdout
passed('effective report is offline and names requested thinking, recipe and origin')
with lock:
    state['tool'] = True
before = counts()[1]
run('--thinking', 'high')
with lock:
    turns = [entry[1] for entry in state['post'][before:]]
    state['tool'] = False
assert len(turns) == 2 and all(turn['output_config']['effort'] == 'high' for turn in turns)
assert any(b.get('type') == 'tool_result' and 'LOCAL_TOOL_RESULT' in str(b) for m in turns[-1]['messages'] for b in m['content'])
passed('both inference requests around an actual read tool retain the policy')
result = run('--thinking', 'high', '--verbose', provider='responses')  # the thinking status is a detail (ADR-0119)
assert body()['reasoning'] == {'effort': 'high', 'summary': 'auto'} and 'support unverified' in result.stderr
run('--thinking', 'off', provider='responses')
assert body()['reasoning'] == {'effort': 'none'}
passed('Responses requests exact high/off fields and reports unknown endpoint support')
before = counts()
run('--thinking', 'high', provider='chat', expect=78)
run('--thinking', 'ultra', expect=64)
assert counts() == before
passed('unimplemented chat controls and invalid CLI spellings send no request')
server.shutdown()
server.server_close()
print('PASS', checks, 'executable checks; ROOT', root)
