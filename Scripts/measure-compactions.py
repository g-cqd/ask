#!/usr/bin/env python3
"""Roadmap 0032: what the context holds before each compaction, in the N largest local sessions.

Scripts/measure-compactions.py N  (reads ~/.local/state/ask/sessions; sizes from each response's recorded usage)
"""
import json, sys, glob, os, statistics, collections
paths = sorted(glob.glob(os.path.expanduser('~/.local/state/ask/sessions/*/*.jsonl')), key=os.path.getsize, reverse=True)[:int(sys.argv[1])]
before, after, gaps, shares = [], [], [], collections.Counter()
models = collections.Counter()
for path in paths:
    entries = []
    for line in open(path, 'rb'):
        try: o = json.loads(line)
        except Exception: continue
        if o.get('type') == 'entry': entries.append(o)
    last_ctx = None; since = 0; window = collections.Counter(); pending_after = False
    for o in entries:
        p = o['payload']; k = p.get('kind')
        if k == 'response':
            u = p.get('usage') or {}
            ctx = u.get('input', 0) + u.get('cacheRead', 0) + u.get('cacheCreation', 0)
            if pending_after: after.append(ctx); pending_after = False
            last_ctx = ctx; since += 1; models[p.get('model')] += 1
            for b in p.get('blocks', []) or []:
                window[b.get('type', '?')] += len(json.dumps(b))
        elif k == 'tool_result':
            window['tool_result'] += len(json.dumps(p))
        elif k == 'user':
            window['user'] += len(json.dumps(p))
        elif k == 'compaction':
            if last_ctx: before.append(last_ctx)
            gaps.append(since); since = 0; pending_after = True
            total = sum(window.values()) or 1
            for t, v in window.items(): shares[t] += v / total
            window = collections.Counter()
n = len(gaps)
q = lambda xs: f"median {statistics.median(xs):,.0f}, p10 {sorted(xs)[len(xs)//10]:,.0f}, p90 {sorted(xs)[len(xs)*9//10]:,.0f}"
print('compactions', n)
print('context tokens at the last request before:', q(before))
print('context tokens at the first request after:', q(after))
print('requests between compactions:', q(gaps))
print('share of the window before each compaction, by bytes:', {t: f"{v/n:.0%}" for t, v in shares.most_common()})
print('models:', dict(models.most_common(5)))
