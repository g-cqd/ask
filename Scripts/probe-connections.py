#!/usr/bin/env python3
"""End-to-end check of named connections and their model aliases, on the real release binary.

    python3 Scripts/probe-connections.py [.build/release/ask]

Everything happens in a temporary directory with synthetic credentials, so it never touches the real sign-ins and sends
nothing over the network: a connection is signed out before any step that would make a request, so ask stops locally with
exit 77. What it checks is what the unit tests cannot: that the commands, exit codes, notices and files agree on the
actual binary. It prints one PASS line per step and stops at the first failure.
"""
import json, os, pathlib, subprocess, sys, tempfile, time, uuid

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-connections-probe-'))
config = root / 'config' / 'ask'
config.mkdir(parents=True, mode=0o700)
env = {**os.environ, 'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_STATE_HOME': str(root / 'state')}
for key in ['ASK_PROVIDER', 'ASK_MODEL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_OAUTH_TOKEN']:
    env.pop(key, None)
SECRETS = ['fixture-access-', 'fixture-refresh-']


def profile(name, account, provider='codex', signed_in=True):
    record = {'id': str(uuid.uuid4()), 'name': name, 'provider': provider, 'authorizationID': str(uuid.uuid4()),
              'accountIdentity': account, 'removed': False, 'authenticatedBefore': True, 'schemaVersion': 1}
    directory = config / 'connections' / record['id']
    directory.mkdir(parents=True, mode=0o700)
    value = {'connection': record}
    if signed_in and provider == 'codex':
        value['codex'] = {'accessToken': 'fixture-access-' + name, 'refreshToken': 'fixture-refresh-' + name,
                          'expiresAt': 1e12, 'accountID': account}
    path = directory / 'credentials.json'
    path.write_text(json.dumps(value))
    path.chmod(0o600)
    scope = {'provider': 'codex', 'accountID': account, 'connectionID': record['id'], 'endpoint': {
        'relative': 'https://chatgpt.com/backend-api/codex/models?client_version=0.163.0'}}
    (directory / 'models-codex.json').write_text(json.dumps({'version': 1, 'scope': scope, 'fetchedAt': time.time(),
        'models': [{'id': 'fixture-model', 'contextWindow': 8192, 'maxOutputTokens': 1024}]}))
    return record, path, directory


def run(args, expected, check=None):
    p = subprocess.run([binary, *args], cwd=root, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                       timeout=20)
    out = p.stdout + p.stderr
    assert p.returncode == expected, (args, p.returncode, out)
    if check:
        assert check(out), (args, out)
    assert not any(secret in out for secret in SECRETS), ('a credential reached the output', args)
    lines = [l for l in out.splitlines() if 'code_challenge' not in l and not l.startswith('  https://')]
    print('PASS', ' '.join(args)[:70].ljust(70), 'exit=%d' % expected, ' | '.join(lines)[:150], flush=True)


def sign_out_fixture(path):
    value = json.loads(path.read_text())
    value.pop('codex', None)
    path.write_text(json.dumps(value))
    path.chmod(0o600)


# --- registration, listing, rename -------------------------------------------------------------------------------------
work, work_path, work_dir = profile('work', 'account-work')
profile('personal', 'account-personal')
run(['connections'], 0, lambda s: 'personal  codex  credentials stored' in s and 'work  codex  credentials stored' in s)
run(['--provider', 'work', '--self-check'], 0, lambda s: 'self-check ok' in s)
run(['connections', 'rename', 'work', 'employer'], 0)
assert json.loads(work_path.read_text())['connection']['id'].lower() == work['id'].lower()
run(['connections', 'rename', 'employer', 'work'], 0)
run(['login', 'codex', '--name', 'groq'], 1, lambda s: 'already belongs' in s)
run(['login', 'codex', '--name', '../escape'], 1, lambda s: '1–64' in s)

# --- aliases and the default ---------------------------------------------------------------------------------------------
run(['connections', 'alias', 'work', 'fast', 'gpt-6-luna', '--context', '8000'], 0, lambda s: 'work/fast is gpt-6-luna' in s)
run(['connections', 'alias', 'work', 'deep', 'gpt-6-sol'], 0)
run(['connections', 'alias', 'work', 'Fast', 'gpt-6-sol'], 0)  # names are lower-cased: this replaces fast
run(['connections', 'alias', 'work', 'fixture-model', 'gpt-6-luna'], 1, lambda s: 'already a model on this account' in s)
run(['connections', 'alias', 'work', 'bad name', 'm'], 1, lambda s: 'lower-case letters' in s)
run(['connections', 'alias', 'work', 'loop', 'loop'], 1, lambda s: 'names itself' in s)
run(['connections', 'alias', 'work', 'chain', 'deep'], 1, lambda s: 'points at another alias' in s)
aliases = json.loads((work_dir / 'aliases.json').read_text())
assert aliases['aliases']['fast']['model'] == 'gpt-6-sol' and 'default' not in aliases, aliases
assert oct((work_dir / 'aliases.json').stat().st_mode & 0o777) == '0o600'
sign_out_fixture(work_path)  # from here a request stops locally, before any network
run(['--provider', 'work', '--model', 'deep', '--print', 'x'], 77,
    lambda s: 'Using work/deep, which is gpt-6-sol.' in s and 'ask login codex --name work' in s)
run(['connections', 'default', 'work', 'fast'], 0)
run(['--provider', 'work', '--print', 'x'], 77, lambda s: 'Using work/fast, which is gpt-6-sol.' in s)
run(['--provider', 'work', '--model', 'gpt-9-unlisted', '--print', 'x'], 77, lambda s: 'Using work/' not in s)
run(['connections', 'unalias', 'work', 'fast'], 1, lambda s: 'is the default model' in s)
run(['connections', 'default', 'work', '--clear'], 0)
run(['connections', 'unalias', 'work', 'fast'], 0)
run(['connections', 'unalias', 'work', 'fast'], 1, lambda s: 'no alias named' in s)
run(['connections', 'default', 'work'], 64)  # neither a model nor --clear: a usage error

# --- a rename keeps the aliases; a damaged file refuses a run that relies on it, not one that names a model ---------------
run(['connections', 'default', 'work', 'deep'], 0)
run(['connections', 'rename', 'work', 'employer'], 0)
run(['--provider', 'employer', '--print', 'x'], 77, lambda s: 'Using employer/deep, which is gpt-6-sol.' in s)
(work_dir / 'aliases.json').write_text('{broken')
run(['--provider', 'employer', '--print', 'x'], 78, lambda s: 'not a valid alias file' in s)
run(['--provider', 'employer', '--model', 'gpt-6-sol', '--print', 'x'], 77, lambda s: 'Aliases not used' in s)
assert (work_dir / 'aliases.json').read_text() == '{broken', 'a damaged file must never be rewritten'

# --- a removed connection starts again with no aliases ---------------------------------------------------------------------
run(['connections', 'remove', 'employer'], 0)
run(['connections'], 0, lambda s: 'employer' not in s)
print('ROOT', root)
