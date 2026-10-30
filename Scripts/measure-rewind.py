#!/usr/bin/env python3
"""What `/rewind N` costs on a long session (roadmap 0160): a copy of SESSION is resumed (the original is never opened), `/rewind N`
is sent, and each run reports how long the screen kept drawing after Enter, and the slowest of five keys typed after it.

    Scripts/measure-rewind.py .build/release/ask SESSION.jsonl [N]
"""
import sys, os, time, shutil, tempfile, select
B=os.path.abspath(sys.argv[1]); S=sys.argv[2]; N=sys.argv[3] if len(sys.argv)>3 else "3"
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'measure-long-session.py')).read().replace('\nmain()\n','\n')
m={}; sys.argv=['x',B,S,'1']; exec(compile(src,'m','exec'),m)
def run():
    root=tempfile.mkdtemp(); p,c,s=[os.path.join(root,n) for n in ('p','c','s')]
    for d in (p,c,s): os.makedirs(d)
    copy=os.path.join(root,'x.jsonl'); shutil.copyfile(S,copy)
    pid,fd=m['spawn'](p,c,s,['--resume',copy])
    try:
        m['read_until'](fd, lambda b: m['RULE'] in b and m['FRAME_END'] in b[b.find(m['RULE']):], 30.0); m['quiet'](fd,0.8)
        os.write(fd,f"/rewind {N}".encode()); m['quiet'](fd,0.3)
        t0=time.monotonic(); os.write(fd,b"\r")
        settled=(m['quiet'](fd,0.5)-t0)*1000
        keys=[]
        for _ in range(5):
            k0=time.monotonic(); os.write(fd,"Ж".encode())
            got=m['read_until'](fd, lambda b: "Ж".encode() in b, 30.0); keys.append((got[0]-k0)*1000 if got else float('nan')); m['quiet'](fd,0.1)
        return round(settled), round(max(keys),1)
    finally:
        try: os.kill(pid,9); os.waitpid(pid,0)
        except OSError: pass
        os.close(fd); shutil.rmtree(root,ignore_errors=True)
print("(settled ms, worst key ms after):", [run() for _ in range(3)])
