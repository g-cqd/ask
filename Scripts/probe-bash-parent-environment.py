#!/usr/bin/env python3
"""Can a command the model runs read ask's own environment out of ask's process? (roadmap 0072, ADR-0112)

Usage: python3 Scripts/probe-bash-parent-environment.py .build/release/ask
Another process of the same user can read a process's original environment with sysctl(KERN_PROCARGS2). The command compiles a small C reader
(through `cc`, so it also runs when reads are restricted) and prints the ANTHROPIC_API_KEY entry of its parent, ask. Stand-in key, local fake
provider, no network. Run twice: the default sandbox and `--read workspace`.

Exit 1 when the stand-in key is recovered, 0 when it is not and the entry was read, 2 when the experiment did not run.
Before ADR-0112 this exited 1 in both modes; Seatbelt does not govern this call (six rules and ask's deny-default read profile were tried).
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], BINARY]
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
KEY = "sk-ant-api-PARENT-ENV-STANDIN-0001"
COMMAND = 'printf \'%s\' \'#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <errno.h>\n#include <sys/sysctl.h>\nint main(int c, char **v) {\n  int mib[3] = {CTL_KERN, KERN_PROCARGS2, atoi(v[1])};\n  size_t n = 0;\n  if (sysctl(mib, 3, NULL, &n, NULL, 0)) { printf("DENIED %d\\\\n", errno); return 0; }\n  char *b = malloc(n);\n  if (sysctl(mib, 3, b, &n, NULL, 0)) { printf("DENIED %d\\\\n", errno); return 0; }\n  for (size_t i = 0; i + 18 < n; i++) if (!memcmp(b + i, "ANTHROPIC_API_KEY=", 18)) printf("%s\\\\n", b + i);\n  printf("SCANNED\\\\n");\n  return 0;\n}\n\' | cc -x c - -o pa 2>&1 | tail -3; ./pa "$PPID"'


def attempt(extra):
    with tempfile.TemporaryDirectory() as root:
        project = root + "/project"
        os.makedirs(project)
        server = agent.Server([agent.turn([("tool", "t1", COMMAND)], "tool_use"), agent.turn([("text", "done")], "end_turn")])
        env = agent.environment(root + "/state", server.url)
        env["ANTHROPIC_API_KEY"] = KEY
        subprocess.run([BINARY, "-p", "run it", *extra], cwd=project, env=env, capture_output=True, text=True, timeout=120,
                       stdin=subprocess.DEVNULL)
        server.httpd.shutdown()
        if len(server.requests) < 2:
            return None
        blocks = [b for m in server.requests[1]["body"]["messages"]
                  for b in (m["content"] if isinstance(m["content"], list) else []) if b.get("type") == "tool_result"]
        return json.dumps(blocks)


def main():
    if sys.platform != "darwin":
        print("invalid experiment: Darwin-only probe")
        return 2
    verdict = 0
    for label, extra in (("default sandbox", []), ("--read workspace", ["--read", "workspace"])):
        text = attempt(extra)
        if text is None or "SCANNED" not in text and "DENIED" not in text:
            print("%-17s invalid experiment: %s" % (label, (text or "no tool result")[:300]))
            return 2
        if KEY in text:
            print("%-17s EXPOSED: the stand-in key was read from ask's process" % label)
            verdict = 1
        else:
            print("%-17s not recovered (%s)" % (label, "denied" if "DENIED" in text else "entry blank"))
    return verdict


sys.exit(main())
