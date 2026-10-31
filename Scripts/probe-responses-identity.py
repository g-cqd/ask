#!/usr/bin/env python3
"""Replay the sanitized rotating-ID Responses recording through ask's real CLI.

No account or network beyond loopback. Check stdout and persisted responses, not
only decoder events. Optional --control BASELINE --runs N alternates binary order
and reports whole-command latency; the known baseline must emit AUDITAUDIT.
"""
import argparse
import http.server
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import threading
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

FIXTURE = Path(__file__).resolve().parent.parent / 'Tests/Fixtures/Responses/copilot-rotating-ids.sse'


def summary(values):
    ordered = sorted(values)
    percentile = lambda p: ordered[max(0, math.ceil(len(ordered) * p) - 1)]
    return dict(samples=len(values), p50=statistics.median(ordered), p25=percentile(.25),
                p75=percentile(.75), p95=percentile(.95))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', nargs='?', default='.build/release/ask')
    parser.add_argument('--control')
    parser.add_argument('--runs', type=int, default=1)
    args = parser.parse_args()
    assert args.runs > 0
    binaries = {'candidate': str(Path(args.binary).resolve())}
    if args.control:
        binaries['control'] = str(Path(args.control).resolve())
    recorded, requests, timings = FIXTURE.read_bytes(), [], {name: [] for name in binaries}
    delivery = {'chunk': 65536}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['content-length'])))
            requests.append((self.path, body))
            self.send_response(200)
            self.send_header('content-type', 'text/event-stream')
            self.end_headers()
            for offset in range(0, len(recorded), delivery['chunk']):
                self.wfile.write(recorded[offset:offset + delivery['chunk']])
                self.wfile.flush()

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix='ask-responses-identity-') as directory:
            root = Path(directory)
            config = root / 'config/ask'
            config.mkdir(parents=True)
            (config / 'providers.json').write_text(json.dumps({'providers': {'fixture': {
                'api': 'openai-responses', 'baseUrl': f'http://127.0.0.1:{server.server_address[1]}/v1',
                'models': [{'id': 'fixture-model'}]}}}))
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith(('ASK_', 'ANTHROPIC_', 'OPENAI_', 'CODEX_'))}
            environment.update(XDG_CONFIG_HOME=str(root / 'config'), HOME=str(root))
            environment["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
            for chunk in [7, 65536]:
                delivery['chunk'] = chunk
                for trial in range(args.runs):
                    order = list(binaries) if trial % 2 == 0 else list(reversed(binaries))
                    for name in order:
                        state = root / f'state-{chunk}-{trial}-{name}'
                        environment['XDG_STATE_HOME'] = str(state)
                        before = len(requests)
                        started = time.monotonic_ns()
                        result = subprocess.run([binaries[name], '--provider', 'fixture', '--model', 'fixture-model',
                                                 '--max-turns', '1', '--print', 'Reply only with AUDIT.'],
                                                cwd=root, env=environment, stdin=subprocess.DEVNULL,
                                                capture_output=True, text=True, timeout=30)
                        timings[name].append((time.monotonic_ns() - started) / 1_000_000)
                        expected = 'AUDIT' if name == 'candidate' else 'AUDITAUDIT'
                        assert result.returncode == 0, (result.returncode, result.stderr)
                        assert result.stdout == expected + '\n', (name, repr(result.stdout))
                        assert len(requests) == before + 1 and requests[-1][0] == '/v1/responses', requests
                        responses = [record['payload'] for path in state.rglob('*.jsonl')
                                     for line in path.read_text().splitlines()
                                     if (record := json.loads(line)).get('payload', {}).get('kind') == 'response']
                        assert len(responses) == 1, responses
                        texts = [block['text'] for block in responses[0]['blocks'] if block.get('type') == 'text']
                        assert ''.join(texts) == expected, (name, texts)
                        if name == 'candidate':
                            assert texts == ['AUDIT'], texts
                        if trial == 0:
                            print(f'PASS {name}: CLI and persisted response = {expected} (delivery chunk {chunk})', flush=True)
            for name, values in timings.items():
                print(name, 'whole_command_ms', json.dumps(summary(values)), flush=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
