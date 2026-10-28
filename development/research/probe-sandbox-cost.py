import subprocess, time, statistics, os, sys
home = os.path.expanduser("~")
full = f'''(version 1)
(allow default)
(deny file-write* (subpath (param "DW0")) (subpath (param "DW1")) (literal (param "DW2")))
(deny file-read* (subpath (param "DR3")) (subpath (param "DR4")) (subpath (param "DR5")) (literal (param "DR6")) (literal (param "DR7")) (literal (param "DR8")))
(deny file-write-unlink (literal (param "A9")) (literal (param "A10")) (literal (param "A11")))
'''
params = [f"-D{n}={home}/{n}" for n in ["DW0","DW1","DW2","DR3","DR4","DR5","DR6","DR7","DR8","A9","A10","A11"]]
cases = {
  "no sandbox: bash -c true": ["/bin/bash", "-c", "true"],
  "sandbox-exec, empty profile": ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)", "/bin/bash", "-c", "true"],
  "sandbox-exec, our 12-rule profile": ["/usr/bin/sandbox-exec", *params, "-p", full, "/bin/bash", "-c", "true"],
  "sandbox-exec, empty profile, /usr/bin/true": ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)", "/usr/bin/true"],
  "/usr/bin/true (no bash, no sandbox)": ["/usr/bin/true"],
}
runs = {k: [] for k in cases}
for i in range(300):
    for name, argv in cases.items():
        t = time.perf_counter(); subprocess.run(argv, check=True, capture_output=True); runs[name].append((time.perf_counter() - t) * 1000)
for name, v in runs.items():
    v.sort(); print(f"{name:46} p50 {statistics.median(v):6.2f} ms   p90 {v[len(v)*9//10]:6.2f}")
