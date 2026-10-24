import subprocess, re, sys, statistics
D='/Users/me/Library/Caches/ask-mutation/'
prompts=[('very common word','Find every use of the word func under Sources/AskAI and tell me roughly how many there are.'),
         ('broad regex','Show me all the async functions declared in Sources/AskAI.')]
res={}
for rnd in range(3):
    for name,prompt in prompts:
        for arm in (['A','B'] if rnd%2==0 else ['B','A']):
            p=subprocess.run([D+'ask-search-'+arm,'--provider','codex','--model','gpt-6.1-sol','--thinking','low','--max-turns','8','--print',prompt],cwd='/Users/me/Developer/ask-search',capture_output=True,text=True,timeout=300,stdin=subprocess.DEVNULL)
            m=re.search(r'tokens in ([\d.]+)(k?) .* out (\d+)',p.stderr)
            tin=float(m.group(1))*(1000 if m.group(2) else 1) if m else -1
            cmds=[l[7:].strip() for l in p.stderr.splitlines() if l.startswith('▸ bash')]
            capped=any(re.search(r'head|-m\s?\d|wc -l|-c\b|--max-count|-o ',c) for c in cmds)
            print(name.ljust(18),arm,'exit',p.returncode,'in %6.0f'%tin,'cmds',len(cmds),'bounded' if capped else 'UNBOUNDED',flush=True)
            res.setdefault((name,arm),[]).append((tin,capped))
print()
for (name,arm),v in sorted(res.items()):
    print(name.ljust(18),arm,'median input tokens %.0f'%statistics.median(t for t,_ in v),'bounded %d/%d'%(sum(c for _,c in v),len(v)))
