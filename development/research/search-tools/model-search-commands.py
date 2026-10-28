import subprocess, re, sys
B='/Users/me/Developer/ask/.build/release/ask'
prompts=[('moderate symbol','List every file in Sources that mentions ProviderFailure, with the number of mentions in each.'),
 ('very common word','Find every use of the word func under Sources/AskAI and tell me roughly how many there are.'),
 ('locate a feature','Where in this repository is the file picker implemented? Name the files.'),
 ('count with a filter','How many test files mention sandbox, ignoring case? Just the number.'),
 ('broad regex','Show me all the async functions declared in Sources/AskAI.')]
for name,prompt in prompts:
    p=subprocess.run([B,'--provider','codex','--model','gpt-6.1-sol','--thinking','low','--max-turns','8','--print',prompt],capture_output=True,text=True,timeout=300,stdin=subprocess.DEVNULL)
    cmds=[l[2:].strip() for l in p.stderr.splitlines() if l.startswith('▸ bash')]
    use=re.search(r'tokens in ([\d.]+k?) .* out (\d+)',p.stderr)
    print('==',name,'| exit',p.returncode,'| usage in/out',use.groups() if use else '?')
    for c in cmds: print('   ',c[:170])
