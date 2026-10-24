import subprocess, time, statistics
Q=[('literal, moderate','rg -n "ProviderFailure" Sources Tests'),('literal, very common','rg -n "func " Sources Tests'),
   ('regex','rg -n "func\\s+\\w+\\(.*async" Sources Tests'),('files by glob',"rg --files -g '*.swift' Sources Tests"),
   ('count only','rg -c "Anthropic" Sources'),('rare, no match','rg -n "zzzzNoSuchSymbolzzzz" Sources Tests')]
def run(cmd,n=25):
    ts=[]
    for _ in range(n):
        t=time.perf_counter(); p=subprocess.run(['/bin/sh','-c',cmd],capture_output=True); ts.append((time.perf_counter()-t)*1000)
    return statistics.median(ts), sorted(ts)[int(0.95*len(ts))-1], p.stdout
base=[]; 
for _ in range(25):
    t=time.perf_counter(); subprocess.run(['/bin/sh','-c',':'],capture_output=True); base.append((time.perf_counter()-t)*1000)
print('shell spawn alone: median %.2f ms'%statistics.median(base))
for name,cmd in Q:
    med,p95,out=run(cmd)
    lines=out.count(b'\n'); capped=b'\n'.join(out.split(b'\n')[:100])
    print('%-22s median %6.2f ms p95 %6.2f | %5d lines %7d B ~%5d tok | capped 100: %6d B ~%4d tok'%(name,med,p95,lines,len(out),len(out)//4,len(capped),len(capped)//4))
