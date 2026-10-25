#!/usr/bin/env python3
"""Local stand-in-only regression for roadmap 0072's unresolved parent-environment exposure.

Usage: python3 Scripts/probe-bash-parent-environment.py .build/release/ask
Exit 1: the sandboxed tool result contains the parent key; 0: sysctl explicitly denied; 2: invalid experiment.
This probes direct Darwin sysctl rather than assuming that blocking /bin/ps blocks process inspection.
No real credentials or remote provider are used.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], BINARY]
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(os.path.dirname(__file__), "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
KEY = "sk-ant-api-PARENT-ENV-STANDIN-0001"
COMMAND = r'''python3 - "$PPID" <<'PY'
import ctypes, ctypes.util, sys
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
mib = (ctypes.c_int * 3)(1, 49, int(sys.argv[1]))
size = ctypes.c_size_t(0)
r = libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0)
if r != 0:
    print("DENIED", ctypes.get_errno())
else:
    buf = ctypes.create_string_buffer(size.value)
    r = libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0)
    if r != 0:
        print("DENIED", ctypes.get_errno())
    else:
        entries = [e for e in buf.raw.split(b'\0') if e.startswith(b'ANTHROPIC_API_KEY=')]
        print("ENTRIES", len(entries))
        for entry in entries:
            print(entry.decode())
PY'''


def main():
    if sys.platform != "darwin":
        print("invalid experiment: Darwin-only probe")
        return 2
    with tempfile.TemporaryDirectory() as root:
        project = root + "/project"
        os.makedirs(project)
        server = agent.Server([agent.turn([("tool", "t1", COMMAND)], "tool_use"), agent.turn([("text", "done")], "end_turn")])
        env = agent.environment(root + "/state", server.url)
        env["ANTHROPIC_API_KEY"] = KEY
        subprocess.run([BINARY, "-p", "run it"], cwd=project, env=env, capture_output=True, text=True,
                       timeout=60, stdin=subprocess.DEVNULL)
        if len(server.requests) < 2:
            print("invalid experiment: no tool result")
            return 2
        blocks = [b for m in server.requests[1]["body"]["messages"]
                  for b in (m["content"] if isinstance(m["content"], list) else []) if b.get("type") == "tool_result"]
        text = json.dumps(blocks)
        if KEY in text:
            print("EXPOSED: sandboxed command recovered the stand-in parent key via KERN_PROCARGS2")
            return 1
        if "DENIED 1" in text or "DENIED 13" in text:
            print("withheld: parent process-argument inspection denied")
            return 0
        print("invalid experiment: neither key recovery nor an explicit permission denial observed")
        return 2


sys.exit(main())
