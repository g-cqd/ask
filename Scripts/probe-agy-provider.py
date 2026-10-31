#!/usr/bin/env python3
"""Release-binary probe of the Antigravity provider's paths that need no network (ADR-0090).

Every run uses throwaway XDG directories, so nothing here reads or writes the real credentials. Usage: probe-agy-provider.py BINARY
"""
import json, os, pathlib, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

binary = os.path.abspath(sys.argv[1])
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-agy-provider-'))
env = {k: v for k, v in os.environ.items() if not k.startswith(('ANTHROPIC_', 'ASK_', 'XDG_', 'AGY_'))}
env |= {'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state'), 'HOME': str(root)}
env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
failures = []

def run(args, expect_code, expect_text=None, forbid_text=None, label=None):
    p = subprocess.run([binary, *args], cwd=root, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    out = p.stdout + p.stderr
    ok = p.returncode == expect_code and (expect_text is None or expect_text in out) and (forbid_text is None or forbid_text not in out)
    print(('PASS' if ok else 'FAIL'), label or ' '.join(args), f'exit={p.returncode}', ('' if ok else '\n   ' + out.strip()[:300]))
    if not ok: failures.append(label or ' '.join(args))

run(['--provider', 'agy', '--print', 'hi'], 78, 'ask models agy', label='agy with no model names how to list models')
run(['--provider', 'agy', '--model', 'gemini-3-flash', '--print', 'hi'], 77, 'not signed in to Antigravity', label='agy signed out is exit 77 with the command to run')
run(['models', 'agy'], 77, 'not signed in to Antigravity', label='models agy signed out is exit 77')
(root / 'config' / 'ask').mkdir(parents=True)
(root / 'config' / 'ask' / 'providers.json').write_text(json.dumps({'providers': {'agy': {'api': 'openai-completions', 'baseUrl': 'http://127.0.0.1:1/v1'}}}))
run(['--provider', 'agy', '--model', 'm', '--print', 'hi'], 78, 'built in', label='a file may not define agy')
(root / 'config' / 'ask' / 'providers.json').unlink()
# the known list names it
run(['--provider', 'nonsense', '--model', 'm', '--print', 'hi'], 78, 'agy', label='the known providers include agy')
# a damaged credential file is reported, not read as signed out
(root / 'config' / 'ask' / 'credentials.json').write_text('{broken')
run(['--provider', 'agy', '--model', 'm', '--print', 'hi'], 77, None, forbid_text='not signed in to Antigravity', label='a damaged credential file is not signed out')
print('FAILURES' if failures else 'ALL PASS', failures)
sys.exit(1 if failures else 0)
