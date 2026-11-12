#!/usr/bin/env python3
"""Roadmap 0032's replay: a summary kept up to date by a cheap model, against the one-shot summary ask wrote, on real compactions.

Scripts/replay-compactions.py [--windows 30] [--sessions 30] [--jobs 6] [--out FILE] [--length CHARS]

For each chosen compaction window of the largest local sessions (Claude sessions only: nothing goes to a provider that had not seen
it), the window is rendered as a transcript (tool output clipped), then:
  1. the cheap model (claude-haiku-5-5) amends a summary chunk by chunk, as a background summariser would;
  2. a stronger model (claude-sonnet-5-5) writes five questions on specific facts from the window's first 40 %;
  3. the stronger model grades each summary, the session's own and the incremental one: does it hold each answer?
Requests go through the installed `ask -p`, from a temporary directory, so they use the person's Anthropic account.
"""
import argparse, concurrent.futures, glob, json, os, re, statistics, subprocess, tempfile

ASK = os.path.expanduser('~/.local/bin/ask')
CHEAP, STRONG = 'claude-haiku-5-5', 'claude-sonnet-5-5'
CHUNK = 60_000


def ask(model, prompt, cwd):
    prompt = prompt.replace('\x00', '')
    run = subprocess.run([ASK, '--provider', 'anthropic', '--model', model, '--thinking', 'off', '--max-turns', '1', '-p', prompt],
                         cwd=cwd, capture_output=True, text=True, timeout=600)
    return run.stdout.strip()


def windows(sessions):
    found = []
    paths = sorted(glob.glob(os.path.expanduser('~/.local/state/ask/sessions/*/*.jsonl')), key=os.path.getsize, reverse=True)
    for path in paths[:sessions]:
        entries, claude = [], True
        for line in open(path, 'rb'):
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get('type') != 'entry':
                continue
            p = o['payload']
            if p.get('kind') == 'response' and not str(p.get('model', '')).startswith('claude'):
                claude = False
            if p.get('kind') == 'compaction':
                if claude and len(entries) > 20:
                    found.append((os.path.basename(path), len(found), entries, p.get('summary', '')))
                entries, claude = [], True
            else:
                entries.append(p)
    return found


def render(entries):
    out = []
    for p in entries:
        k = p.get('kind')
        if k == 'user':
            out.append('USER: ' + p.get('text', ''))
        elif k == 'response':
            for b in p.get('blocks', []) or []:
                if b.get('type') == 'text' and b.get('text'):
                    out.append('ASSISTANT: ' + b['text'])
                elif b.get('type') == 'tool_call':
                    out.append(f"TOOL CALL {b.get('name')}: " + json.dumps(b.get('input', ''))[:400])
        elif k == 'tool_result':
            c = p.get('content', '')
            c = c if isinstance(c, str) else json.dumps(c)
            out.append('TOOL RESULT: ' + (c[:1500] + ' [clipped]' if len(c) > 1500 else c))
    return '\n'.join(out)


LENGTH = 0


def incremental(text, cwd):
    summary = ''
    chunks = [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)]
    for chunk in chunks:
        summary = ask(CHEAP, (
            'You keep a running summary of a coding agent\'s conversation, so the agent can continue the work without the original '
            'messages. Include the user\'s goals and constraints, decisions and why, files read or changed with paths, commands run and '
            'what they showed, exact identifiers, values and error messages that still matter, what is done, in progress and next. '
            + (f'Keep everything in the current summary that still matters, and aim for about {LENGTH:,} characters. ' if LENGTH else '')
            + 'Do not call tools. Reply with the updated summary only.\n\n'
            f'CURRENT SUMMARY:\n{summary or "(none yet)"}\n\nNEW MESSAGES:\n{chunk}'), cwd)
    return summary, len(chunks)


def questions(text, cwd):
    early = text[:int(len(text) * 0.4)][:120_000]
    reply = ask(STRONG, (
        'Below is the early part of a coding agent\'s conversation. Write 5 questions whose answers are specific facts stated in it '
        'that would still matter later (paths, values, decisions and why, errors, the user\'s constraints), each with its short '
        'answer. Do not call tools. Reply with JSON only: [{"q": "...", "a": "..."}].\n\n' + early), cwd)
    match = re.search(r'\[.*\]', reply, re.S)
    return json.loads(match.group(0)) if match else []


def grade(summary, qa, cwd):
    reply = ask(STRONG, (
        'For each question, answer 1 if the summary below contains the information needed to give the reference answer, else 0. '
        'Judge only from the summary. Do not call tools. Reply with JSON only: a list of 0 and 1, one per question.\n\n'
        f'SUMMARY:\n{summary}\n\nQUESTIONS AND REFERENCE ANSWERS:\n' + json.dumps(qa, ensure_ascii=False)), cwd)
    match = re.search(r'\[[\s01,]*\]', reply)
    return json.loads(match.group(0)) if match else None


def one(window, cwd):
    name, index, entries, original = window
    text = render(entries)
    qa = questions(text, cwd)
    if len(qa) < 3:
        return {'session': name, 'window': index, 'error': 'no questions'}
    kept, calls = incremental(text, cwd)
    return {'session': name, 'window': index, 'chars': len(text), 'calls': calls, 'questions': len(qa), 'qa': qa,
            'oneShot': grade(original, qa, cwd), 'incremental': grade(kept, qa, cwd),
            'oneShotChars': len(original), 'incrementalChars': len(kept)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--windows', type=int, default=30)
    parser.add_argument('--sessions', type=int, default=30)
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--out', default='/tmp/replay-compactions.json')
    parser.add_argument('--length', type=int, default=0, help='the length the incremental summary aims at, in characters')
    options = parser.parse_args()
    global LENGTH
    LENGTH = options.length
    every = windows(options.sessions)
    step = max(1, len(every) // options.windows)
    chosen = every[::step][:options.windows]
    print(f'{len(every)} Claude compaction windows; replaying {len(chosen)}', flush=True)
    cwd = tempfile.mkdtemp(prefix='ask-replay-')
    results = []
    with concurrent.futures.ThreadPoolExecutor(options.jobs) as pool:
        def guarded(window):
            try:
                return one(window, cwd)
            except Exception as error:  # one window's failure is reported, the rest go on
                return {'session': window[0], 'window': window[1], 'error': str(error)[:200]}

        for result in pool.map(guarded, chosen):
            results.append(result)
            print(json.dumps(result), flush=True)
    json.dump(results, open(options.out, 'w'), indent=1)
    good = [r for r in results if r.get('oneShot') and r.get('incremental') and len(r['oneShot']) == len(r['incremental'])]
    share = lambda key: statistics.mean(sum(r[key]) / len(r[key]) for r in good)
    print(f'graded {len(good)} of {len(results)}: one-shot {share("oneShot"):.0%} of early facts kept, incremental {share("incremental"):.0%}')
    print(f'summary length median: one-shot {statistics.median(r["oneShotChars"] for r in good):,.0f} chars, '
          f'incremental {statistics.median(r["incrementalChars"] for r in good):,.0f}; cheap calls per window median '
          f'{statistics.median(r["calls"] for r in good)}')


if __name__ == '__main__':
    main()
