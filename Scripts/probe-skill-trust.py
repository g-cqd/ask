#!/usr/bin/env python3
"""A project skill trusted while ask runs reaches the model at the next message, through the real binary, two PTYs and a scripted
provider.

Scripts/probe-skill-trust.py .build/release/ask

ask starts in a project whose skill is not trusted, and a first message goes. `ask trust --skills` with no terminal refuses and says
to use another terminal; in a terminal of its own, beside the running ask, it trusts the skill. The next message carries a note
naming the skill, the screen says it is now offered, and the model's skill call loads it, with no restart. pyte, not a physical
terminal.
"""
import importlib.util
import json
import os
import pty
import select
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check


def in_a_terminal(arguments, cwd, environment):
    """What `arguments` prints with a terminal of its own, and its exit status."""
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execve(arguments[0], arguments, environment)
    output = b""
    while True:
        ready, _, _ = select.select([fd], [], [], 10)
        if not ready:
            break
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        output += chunk
    _, status = os.waitpid(pid, 0)
    return output.decode(errors="replace"), os.waitstatus_to_exitcode(status)


def main():
    root = tempfile.mkdtemp(prefix="probe-skill-trust-")
    project, config = root + "/project", root + "/config"
    folder = project + "/.agents/skills/deploy-check"
    os.makedirs(folder)
    os.makedirs(config + "/ask")
    with open(folder + "/SKILL.md", "w") as file:
        file.write("---\nname: deploy-check\ndescription: Checks a deploy before it ships.\n---\n# DEPLOY CHECK BODY\n")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> ", "separator": "off"}}, file)
    turn = agent.turn
    server = agent.Server([
        turn([("text", "FIRST DONE")], "end_turn"),
        turn([("call", "s1", "skill", {"name": "deploy-check"})], "tool_use"),
        turn([("text", "SECOND DONE")], "end_turn"),
    ])
    environment = agent.environment(root + "/state", server.url, config=config)
    environment.update(TERM="xterm-256color", LANG="en_US.UTF-8", XDG_CONFIG_HOME=config)
    terminal = folding.Terminal(project, environment, columns=160)
    try:
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Hello\r")
        terminal.until(lambda: "FIRST DONE" in terminal.text())
        first = json.dumps(server.requests[0]["body"])
        check("the first request offers no deploy-check: it is not trusted", "deploy-check" not in first)

        refused = subprocess.run([folding.BINARY, "trust", "--skills"], cwd=project, env=environment, stdin=subprocess.DEVNULL,
                                 capture_output=True, text=True)
        print("refused:", refused.returncode, (refused.stderr + refused.stdout).strip())
        check("with no terminal, ask trust refuses and says where it works",
              refused.returncode == 77 and "Open another terminal" in refused.stderr + refused.stdout)
        said, status = in_a_terminal([folding.BINARY, "trust", "--skills"], project, environment)
        print("trusted:", status, said.strip().splitlines()[:2])
        check("in a terminal of its own, it trusts the skill", status == 0 and "Trusted deploy-check" in said)

        terminal.send(b"Ship it\r")
        terminal.until(lambda: "SECOND DONE" in terminal.text())
        check("the screen says the skill is now offered", "now offered to the model: deploy-check" in terminal.text())
        second = json.dumps(server.requests[1]["body"])
        check("the next message names it to the model", "Skills the user trusted during this session" in second
              and "deploy-check" in second)
        loaded = json.dumps(server.requests[2]["body"])
        check("and the model's skill call loads it, with no restart", "DEPLOY CHECK BODY" in loaded)
    except AssertionError:
        print(terminal.text(), file=sys.stderr)
        raise
    finally:
        terminal.close()
        server.httpd.shutdown()
        subprocess.run(["rm", "-rf", root])


if __name__ == "__main__":
    main()
