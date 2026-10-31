#!/usr/bin/env python3
"""What the real `ask login agy` does against the real `agy` binary and Google's real token endpoint, with no account.

    python3 Scripts/probe-agy-login.py [.build/release/ask]

Needs `agy` installed and the network. Everything else is a temporary directory. It checks that the printed authorize URL equals the
one `agy` itself prints (same parameters, challenge and state aside), that every failure exits cleanly and leaves no credential
behind, that a well-formed but fake code gets Google's own refusal, and that `logout agy` removes only Antigravity's record. The
client secret must appear in no output. Prints one PASS line per step and stops at the first failure.
"""
import json, os, pathlib, re, subprocess, sys, tempfile, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

binary = str(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask').resolve())
root = pathlib.Path(tempfile.mkdtemp(prefix='ask-agy-login-probe-'))
config = root / 'config'
creds = config / 'ask' / 'credentials.json'
base_env = {k: v for k, v in os.environ.items() if not k.startswith(('ASK_', 'XDG_', 'AGY_'))}
base_env |= {'XDG_CONFIG_HOME': str(config), 'XDG_STATE_HOME': str(root / 'state')}
base_env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
SECRET_RE = re.compile(r'GOCSPX-[A-Za-z0-9_-]{10,}')


def ask(args, stdin='', env_extra=None):
    p = subprocess.run([binary, *args], cwd=root, env=base_env | (env_extra or {}), input=stdin, capture_output=True, text=True, timeout=60)
    out = p.stdout + p.stderr
    assert not SECRET_RE.search(out), ('a client secret reached the output', args)
    return p.returncode, p.stdout, p.stderr


def url_of(text):
    return re.search(r'https://accounts\.google\.com\S+', text).group(0)


def params(url):
    return urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query, keep_blank_values=True)


def passed(name):
    print('PASS', name, flush=True)


# The reference: what the shipped agy prints for its own sign-in, in a profile that has never signed in.
home = root / 'agyhome'
home.mkdir()
agy_env = base_env | {'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_STATE_HOME': str(home / '.state'), 'XDG_DATA_HOME': str(home / '.data')}
try:
    got = subprocess.run(['agy', '--print', 'hi'], cwd=root, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15, env=agy_env)
    reference_text = got.stdout + got.stderr
except subprocess.TimeoutExpired as waiting:  # agy waits 60 s for a sign-in; the URL is printed first
    reference_text = ((waiting.stdout or b'').decode() if isinstance(waiting.stdout, bytes) else (waiting.stdout or '')) + \
        ((waiting.stderr or b'').decode() if isinstance(waiting.stderr, bytes) else (waiting.stderr or ''))
reference = params(url_of(reference_text))

code, out, err = ask(['login', 'agy'])
assert code == 66 and 'no code entered' in err, (code, out, err)
mine = params(url_of(out))
assert [k for k, _ in mine] == [k for k, _ in reference], (mine, reference)
for (k, v), (_, w) in zip(mine, reference):
    if k in ('code_challenge', 'state'):
        assert len(v) == len(w) and re.fullmatch(r'[A-Za-z0-9_-]+', v), (k, len(v), len(w))
    else:
        assert v == w, (k, v, w)
assert not creds.exists(), 'a sign-in that was never completed left credentials'
passed('the printed URL equals agy\'s own (%d parameters; challenge and state differ only in value), nothing is stored' % len(mine))

fake = root / 'noagy'
fake.write_bytes(os.urandom(4096))
code, out, err = ask(['login', 'agy'], env_extra={'AGY_BINARY': str(fake)})
assert code == 77 and 'holds no OAuth client secret' in err and 'Open this URL' not in out, (code, out, err)
passed('a binary with no secret is refused before any URL is shown')

decoy = root / 'decoyagy'
decoy.write_bytes(os.urandom(512) + b'GOCSPX-' + b'Q' * 28 + os.urandom(512))
code, out, err = ask(['login', 'agy'], env_extra={'AGY_BINARY': str(decoy)})
assert code == 77 and 'accepted by Google' in err and 'Open this URL' not in out, (code, out, err)
passed('a decoy secret Google rejects is refused before any URL is shown')

code, out, err = ask(['login', 'agy'], env_extra={'AGY_BINARY': str(root / 'does-not-exist')})
assert code == 77 and 'cannot read' in err, (code, out, err)
passed('an override that is not a file is reported by name')

code, out, err = ask(['login', 'agy'], stdin='this is not a code\n')
assert code == 77 and 'not the code from this sign-in' in err and not creds.exists(), (code, out, err)
passed('a paste that is not a code stops before any request and stores nothing')

code, out, err = ask(['login', 'agy'], stdin='4/0AfakeFakeFakeFakeFake12345\n')
assert code == 77 and 'HTTP 400' in err and 'invalid_grant' in err and 'ask login agy' in err and not creds.exists(), (code, out, err)
passed('a well-formed fake code gets Google\'s own refusal, worded as what to do, and stores nothing')

code, out, err = ask(['login', 'agy', '--name', 'x'])
assert code == 64 and 'Named sign-ins' in err, (code, out, err)
passed('a named sign-in is refused for agy, as the connection kinds do not include it yet')

(config / 'ask').mkdir(parents=True, mode=0o700, exist_ok=True)
creds.write_text(json.dumps({'agy': {'accessToken': 'a', 'refreshToken': 'r', 'expiresAt': 9},
                             'claude': {'accessToken': 'c', 'refreshToken': 'r', 'expiresAt': 9, 'scopes': 's'}}))
creds.chmod(0o600)
code, out, err = ask(['logout', 'agy'])
kept = json.loads(creds.read_text())
assert code == 0 and 'agy' not in kept and 'claude' in kept, (code, kept)
passed('logout agy removes Antigravity\'s record and keeps Claude\'s')
print('ROOT', root)
