#!/usr/bin/env python3
"""A job the model left running tells it when it ends (owner, 2026-11-27), checked on the built ask in a terminal.

1. The model starts a slow command that bash leaves running as a job, then ends its turn without waiting.
2. When the command ends, ask starts the next turn by itself: the request holds the job's end and what it printed.
3. While the model works on something else, a job that ends goes in as a message at its next step, without a turn of its own.
Exits non-zero on the first failure.
"""
import importlib.util, json, os, sys, tempfile, time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(here, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + ("" if condition else f": {str(detail)[-800:]}"))
    if not condition:
        sys.exit(1)


def call(id, arguments):
    return ("call", id, "bash", arguments)


def last_user_text(request):
    messages = request["body"]["messages"]
    texts = []
    for block in messages[-1]["content"] if isinstance(messages[-1]["content"], list) else [messages[-1]["content"]]:
        if isinstance(block, str):
            texts.append(block)
        elif block.get("type") == "text":
            texts.append(block["text"])
        elif block.get("type") == "tool_result":
            content = block.get("content")
            texts.append(content if isinstance(content, str) else json.dumps(content))
    return "\n".join(texts)


with tempfile.TemporaryDirectory() as root:
    project, config = root + "/project", root + "/config"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as f:
        f.write('{"ui":{"inputPrefix":"ask> "}}')
    server = agent.Server([
        # Turn 1: start a slow command, left running after a second, and end the turn.
        agent.turn([call("t1", {"command": "sleep 4; echo first-job-done", "yield_seconds": 1})], "tool_use"),
        agent.turn([("text", "Started it; I will carry on when it ends.")], "end_turn"),
        # Turn 2, started by the job's end.
        agent.turn([("text", "PICKED UP THE FIRST JOB")], "end_turn"),
        # Turn 3: start another job, then work on something else that takes longer.
        agent.turn([call("t2", {"command": "sleep 2; echo second-job-done", "yield_seconds": 1})], "tool_use"),
        agent.turn([call("t3", {"command": "sleep 5; echo other-work-done"})], "tool_use"),
        agent.turn([("text", "BOTH IN ONE STEP")], "end_turn"),
    ])
    env = agent.environment(root + "/state", server.url, config=config)
    env.update(TERM="xterm-256color", LANG="en_US.UTF-8")
    terminal = folding.Terminal(project, env)
    try:
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Build it\r")
        terminal.until(lambda: "carry on when it ends" in terminal.text())
        requests_after_turn = len([r for r in server.requests if r["body"].get("messages")])
        check("the turn ended while the job runs", requests_after_turn == 2, requests_after_turn)
        started = time.time()
        terminal.until(lambda: "PICKED UP THE FIRST JOB" in terminal.text())
        check("ask started the next turn by itself when the job ended", True)
        bodies = [r for r in server.requests if r["body"].get("messages")]
        told = last_user_text(bodies[-1])
        check("the request holds the job's end", "which you left running, ended" in told, told)
        check("and what it printed", "first-job-done" in told, told)
        check("it came after the job's few seconds, not at once", time.time() - started < 30)

        count = len(bodies)
        terminal.send(b"Now the second\r")
        terminal.until(lambda: "BOTH IN ONE STEP" in terminal.text())
        bodies = [r for r in server.requests if r["body"].get("messages")]
        step = last_user_text(bodies[-1])
        check("a job ending mid-turn goes in at the next step, beside the tool's result",
              "second-job-done" in step and "other-work-done" in step, step)
        check("without a turn of its own", len(bodies) == count + 3, len(bodies) - count)
    finally:
        terminal.close()
print("PROBE PASS")
