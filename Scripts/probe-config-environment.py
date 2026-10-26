#!/usr/bin/env python3
"""The `environment` configuration, end to end through the real executable (roadmap 0028, ADR-0106).

Usage: python3 Scripts/probe-config-environment.py .build/release/ask
Stand-in keys only, a local fake provider, a temporary HOME and configuration. Exit 0 all hold, 1 one failed, 2 the experiment could not run.

  1. a user file's `pass` reaches a command and its `withhold` hides another variable; `ask config` names them, never a value;
  2. a name in both lists is withheld;
  3. a project file that passes a variable is refused by `ask trust` and stays ignored, and the key stays withheld;
  4. a project file that only withholds is trusted and takes effect;
  5. withholding a variable ask itself uses to find its files (XDG_STATE_HOME) hides it from commands without moving the session (ADR-0113).
     A build with that defect writes its session under the real home directory, which this probe cannot see or clean up.
"""
import importlib.util
import json
import os
import pty
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], ASK]
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

OPENAI, SERVICE, ANTHROPIC = "stand-in-openai-0001", "stand-in-service-0002", "stand-in-anthropic-0003"
SHOW = 'echo "OPENAI=[$OPENAI_API_KEY] SERVICE=[$MY_SERVICE_TOKEN] ANTHROPIC=[$ANTHROPIC_API_KEY]"'


class Case:
    def __init__(self, user=None, project=None):
        self.dir = tempfile.TemporaryDirectory()
        root = self.dir.name
        self.project, self.state, self.config = root + "/project", root + "/state", root + "/config"
        os.makedirs(self.project + "/.ask")
        os.makedirs(self.config + "/ask")
        if user is not None:
            json.dump(user, open(self.config + "/ask/config.json", "w"))
        if project is not None:
            json.dump(project, open(self.project + "/.ask/config.json", "w"))
        self.server = agent.Server([agent.turn([("tool", "t1", SHOW)], "tool_use"), agent.turn([("text", "done")], "end_turn")])

    def env(self):
        env = agent.environment(self.state, self.server.url, config=self.config)
        env.update(OPENAI_API_KEY=OPENAI, MY_SERVICE_TOKEN=SERVICE, ANTHROPIC_API_KEY=ANTHROPIC)
        return env

    def ask(self, *args, terminal=False):
        master, slave = pty.openpty() if terminal else (None, None)
        try:
            return subprocess.run([ASK, *args], cwd=self.project, env=self.env(), capture_output=True, text=True, timeout=60,
                                  stdin=slave if terminal else subprocess.DEVNULL)
        finally:
            for fd in (slave, master):
                if fd is not None:
                    os.close(fd)

    def seen(self):
        """What the command printed, by name, from the tool result in the second request; None when there was none."""
        self.ask("-p", "show")
        if len(self.server.requests) < 2:
            return None
        blocks = [b for m in self.server.requests[1]["body"]["messages"]
                  for b in (m["content"] if isinstance(m["content"], list) else []) if b.get("type") == "tool_result"]
        text = json.dumps(blocks)
        return {n: (re.search(n + r"=\[([^\]]*)\]", text) or [None, None])[1] for n in ("OPENAI", "SERVICE", "ANTHROPIC")}

    def close(self):
        self.server.httpd.shutdown()
        self.dir.cleanup()


def main():
    ok = []
    check = lambda label, condition, detail="": ok.append(agent.check(label, condition, detail))

    print("1: a user's pass and withhold")
    case = Case(user={"environment": {"pass": ["OPENAI_API_KEY"], "withhold": ["MY_SERVICE_TOKEN"]}})
    seen = case.seen()
    shown = case.ask("config")
    case.close()
    if seen is None:
        print("invalid experiment: no tool result")
        return 2
    check("a passed preset key reaches the command", seen["OPENAI"] == OPENAI, seen)
    check("a withheld variable does not", seen["SERVICE"] == "", seen)
    check("the Anthropic key stays withheld", seen["ANTHROPIC"] == "", seen)
    check("ask config names both and shows no value",
          "OPENAI_API_KEY" in shown.stdout and "MY_SERVICE_TOKEN" in shown.stdout
          and not any(v in shown.stdout + shown.stderr for v in (OPENAI, SERVICE, ANTHROPIC)), shown.stdout)
    check("and its label is not cut off", re.search(r"^environment +\S", shown.stdout, re.M) is not None, shown.stdout)

    print("2: withholding beats passing")
    case = Case(user={"environment": {"pass": ["OPENAI_API_KEY"], "withhold": ["OPENAI_API_KEY"]}})
    seen = case.seen()
    case.close()
    if seen is None:
        print("invalid experiment: no tool result")
        return 2
    check("a name in both lists is withheld", seen["OPENAI"] == "", seen)

    print("3: a project cannot pass")
    case = Case(project={"environment": {"pass": ["ANTHROPIC_API_KEY"]}})
    refused = case.ask("trust", terminal=True)
    seen = case.seen()
    shown = case.ask("config")
    case.close()
    check("ask trust refuses the file, naming the key", refused.returncode == 78 and "environment.pass" in refused.stderr,
          f"{refused.returncode} {refused.stderr}")
    check("the file stays ignored", "(ignored)" in shown.stdout, shown.stdout)
    check("and the key stays withheld", seen is not None and seen["ANTHROPIC"] == "", seen)

    print("4: a project may withhold more")
    case = Case(project={"environment": {"withhold": ["MY_SERVICE_TOKEN"]}})
    before = case.seen()
    trusted = case.ask("trust", terminal=True)
    case.server.responses[:] = [agent.turn([("tool", "t1", SHOW)], "tool_use"), agent.turn([("text", "done")], "end_turn")]
    case.server.requests.clear()
    after = case.seen()
    case.close()
    if before is None or after is None:
        print("invalid experiment: no tool result")
        return 2
    check("untrusted, its withholding does not apply", before["SERVICE"] == SERVICE, before)
    check("ask trust accepts it", trusted.returncode == 0, trusted.stderr)
    check("trusted, the variable is withheld", after["SERVICE"] == "", after)
    print("5: withholding a path variable does not move ask's own files")
    case = Case(user={"environment": {"withhold": ["XDG_STATE_HOME"]}})
    run = case.ask("-p", "hi")
    kept = [f for _, _, names in os.walk(case.state) for f in names if f.endswith(".jsonl")]
    case.close()
    check("the run succeeds", run.returncode == 0, run.stderr[-300:])
    check("the session is written where XDG_STATE_HOME says", len(kept) == 1, (kept, run.stderr[-200:]))
    return 0 if all(ok) else 1


sys.exit(main())
