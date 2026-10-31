#!/usr/bin/env python3
"""Roadmap 0092 on the real binary: a model two Codex accounts serve is one row of `/model`, its accounts listed once it is chosen,
and the account chosen is remembered for it.

    ASK_PYTE=/tmp/ask-pty/lib python3 Scripts/probe-model-accounts.py [.build/release/ask]

Synthetic credentials and cached model lists in a temporary directory: nothing is sent to Codex, no real sign-in is touched.
"""
import importlib.util, json, os, sys, time, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
picker = importlib.util.module_from_spec(spec)
saved, sys.argv = sys.argv, [sys.argv[0]]
spec.loader.exec_module(picker)
sys.argv = saved
ENDPOINT = {'relative': 'https://chatgpt.com/backend-api/codex/models?client_version=0.163.0'}


def codex(account, name):
    return {'accessToken': 'fixture-access-' + name, 'refreshToken': 'fixture-refresh-' + name, 'expiresAt': 1e12,
            'accountID': account}


def cache(directory, account, models, connection=None):
    scope = {'provider': 'codex', 'accountID': account, 'endpoint': ENDPOINT}
    if connection:
        scope['connectionID'] = connection
    with open(directory + '/models-codex.json', 'w') as file:
        json.dump({'version': 1, 'scope': scope, 'fetchedAt': time.time(),
                   'models': [{'id': m, 'contextWindow': 272000, 'maxOutputTokens': 1024} for m in models]}, file)


def prepare(project):
    config = os.path.dirname(project) + '/config/ask'
    with open(config + '/credentials.json', 'w') as file:
        json.dump({'codex': codex('acct_1', 'default')}, file)
    os.chmod(config + '/credentials.json', 0o600)
    cache(config, 'acct_1', ['gpt-6', 'gpt-6-mini'])
    record = {'id': str(uuid.uuid4()), 'name': 'codex-2', 'provider': 'codex', 'authorizationID': str(uuid.uuid4()),
              'accountIdentity': 'acct_2', 'removed': False, 'authenticatedBefore': True, 'schemaVersion': 1}
    directory = config + '/connections/' + record['id']
    os.makedirs(directory, mode=0o700)
    with open(directory + '/credentials.json', 'w') as file:
        json.dump({'connection': record, 'codex': codex('acct_2', 'second')}, file)
    os.chmod(directory + '/credentials.json', 0o600)
    cache(directory, 'acct_2', ['gpt-6'], connection=record['id'])


def text(terminal):
    return '\n'.join(picker.rows(terminal))


def main():
    binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.build/release/ask')
    with picker.Session(binary, [], prepare=prepare) as session:
        terminal = session.terminal
        memory = os.path.dirname(session.project) + '/config/ask/model-accounts.json'
        picker.type_text(terminal, '/model gpt-6')
        terminal.until(lambda: 'codex · codex-2' in text(terminal))
        shown = text(terminal)
        picker.check('the shared model is one row naming both accounts', 'codex · codex-2 · choose the account next' in shown)
        picker.check('its accounts are not listed before it is chosen', 'gpt-6 · codex-2' not in shown)
        picker.check('a model one account serves keeps its own row', 'codex/gpt-6-mini' in shown)
        picker.press(terminal, b'\r')
        terminal.until(lambda: 'gpt-6 · codex-2' in text(terminal))
        shown = text(terminal)
        picker.check('choosing it writes the model in the draft', picker.prompt_row(terminal).startswith('ask> /model gpt-6'))
        picker.check('and lists each account', 'gpt-6 · codex ' in shown + ' ' and 'gpt-6 · codex-2' in shown)
        picker.type_text(terminal, '2')
        picker.press(terminal, b'\r')
        terminal.until(lambda: 'Model selected' in terminal.text() or 'Model not changed' in terminal.text())
        picker.check('choosing an account selects the model with it', 'Model selected for this run: gpt-6' in terminal.text())
        terminal.until(lambda: os.path.exists(memory))
        with open(memory) as file:
            picker.check('the account is remembered for the model', json.load(file) == {'codex/gpt-6': 'codex-2'})
        # A model that takes an effort fills the draft with `/thinking `; it is cleared first.
        terminal.until(lambda: '/thinking' in picker.prompt_row(terminal))
        for _ in range(len('/thinking ')):
            picker.press(terminal, b'\x7f')
        picker.type_text(terminal, '/model gpt-6')
        terminal.until(lambda: 'codex-2, of codex-2 · codex' in text(terminal))
        picker.check('next time the row says which account it runs with', 'codex-2, of codex-2 · codex' in text(terminal))
    print('PASS', len(picker.checks), 'checks')


main()
