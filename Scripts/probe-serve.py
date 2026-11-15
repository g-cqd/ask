#!/usr/bin/env python3
"""Roadmap 0234 step 2: `ask serve` speaks the Agent Client Protocol on its standard streams (ADR-0153), each session a
conversation of its own in the folder the client names (ADR-0154). Driven here over pipes, against the local fake model server,
from a working directory that is none of the sessions'.

A: one session: initialize, session/new, a prompt with two tool calls in it, a second prompt. The model's words arrive as chunks,
   in order, before the answer; each call is told as it begins and ends; the read was of the session's folder; the write asks the
   client, which allows the first and denies the second; the session file is the one the id names.
B: two sessions in two folders: each keeps its own file and its own history.
C: nothing but protocol messages on standard output, and ask ends when its input does.
D: a second `ask serve` loads the first session: its prompts, answers and calls are replayed in order before the answer, and the
   next prompt continues it in the same file.

Scripts/probe-serve.py .build/release/ask
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
saved, sys.argv = sys.argv, sys.argv[:1]
spec.loader.exec_module(agent)
sys.argv = saved


class Client:
    """An ACP client over the pipes of one `ask serve`: a request, then every message read until its answer."""

    def __init__(self, binary, cwd, env):
        self.process = subprocess.Popen([binary, "serve"], cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
        self.next_id, self.lines, self.not_json = 1, [], []
        # The option chosen for each permission ask makes, in order; "once" when the list is used up.
        self.choices, self.asked = [], []

    def request(self, method, params):
        """The answer to the request, and the notifications that came before it."""
        identifier, self.next_id = self.next_id, self.next_id + 1
        message = {"jsonrpc": "2.0", "id": identifier, "method": method, "params": params}
        self.process.stdin.write((json.dumps(message) + "\n").encode())
        self.process.stdin.flush()
        before = []
        while True:
            line = self.process.stdout.readline()
            if not line:
                return {"error": {"message": "ask ended before it answered: " + self.process.stderr.read().decode()[-400:]}}, before
            self.lines.append(line)
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError:
                self.not_json.append(line)
                continue
            if parsed.get("id") == identifier and "method" not in parsed:
                return parsed, before
            before.append(parsed)
            if parsed.get("method") == "session/request_permission":
                self.asked.append(parsed["params"])
                chosen = self.choices.pop(0) if self.choices else "once"
                reply = {"jsonrpc": "2.0", "id": parsed["id"], "result": {"outcome": {"outcome": "selected", "optionId": chosen}}}
                self.process.stdin.write((json.dumps(reply) + "\n").encode())
                self.process.stdin.flush()

    def close(self):
        """Ends the input; returns ask's exit status and what it said on standard error."""
        self.process.stdin.close()
        try:
            status = self.process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.process.kill()
            status = "still running 20 s after its input ended"
        return status, self.process.stderr.read().decode()


def chunks(messages, kind, session):
    return "".join(m["params"]["update"]["content"]["text"] for m in messages
                   if m.get("method") == "session/update" and m["params"]["sessionId"] == session
                   and m["params"]["update"]["sessionUpdate"] == kind)


def calls(messages, call):
    """The updates about tool call `call`, in order."""
    return [m["params"]["update"] for m in messages
            if m.get("method") == "session/update" and m["params"]["update"].get("toolCallId") == call]


def prompt(session, text):
    return {"sessionId": session, "prompt": [{"type": "text", "text": text}]}


def main():
    binary = os.path.abspath(sys.argv[1])
    root = os.path.realpath(tempfile.mkdtemp())
    one, two, elsewhere = (os.path.join(root, name) for name in ("one", "two", "elsewhere"))
    for folder in (one, two, elsewhere):
        os.mkdir(folder)
    with open(os.path.join(one, "note.txt"), "w") as note:
        note.write("the note of one\n")
    server = agent.Server([
        agent.turn([("text", "Reading. "), ("call", "t1", "read", {"path": "note.txt"})], "tool_use"),
        agent.turn([("call", "t2", "write", {"path": "made.txt", "content": "made by serve\n"})], "tool_use"),
        agent.turn([("text", "It says: the note of one.")], "end_turn"),
        agent.turn([("call", "t3", "write", {"path": "refused.txt", "content": "never\n"})], "tool_use"),
        agent.turn([("text", "Second answer.")], "end_turn"),
        agent.turn([("text", "Hello from two.")], "end_turn"),
        agent.turn([("text", "Continued.")], "end_turn"),
    ])
    state = os.path.join(root, "state")
    client = Client(binary, elsewhere, agent.environment(state, server.url))

    print("A: one session")
    opened, _ = client.request("initialize", {"protocolVersion": 1, "clientCapabilities": {}})
    made, _ = client.request("session/new", {"cwd": one, "mcpServers": []})
    session = made.get("result", {}).get("sessionId", "")
    answer, before = client.request("session/prompt", prompt(session, "What does note.txt say?"))
    files = agent.sessions(state)
    results = [
        agent.check("initialize answers version 1", opened.get("result", {}).get("protocolVersion") == 1, opened),
        agent.check("session/new answers an id", bool(session), made),
        agent.check("the turn ends with end_turn", answer.get("result") == {"stopReason": "end_turn"}, answer),
        agent.check("the model's words came as chunks, in order, before the answer",
                    chunks(before, "agent_message_chunk", session) == "Reading. It says: the note of one.", before),
        agent.check("every update names the session", all(m.get("params", {}).get("sessionId") == session for m in before), before),
        agent.check("the read was of the session's folder, not of the one ask was started in",
                    len(server.requests) >= 2 and "the note of one" in json.dumps(server.requests[1]["body"]["messages"][-1]),
                    server.requests[1]["body"]["messages"][-1] if len(server.requests) >= 2 else "no second request"),
        agent.check("the read is told as a tool call of the session's folder, begun then completed",
                    [(u.get("sessionUpdate"), u.get("status")) for u in calls(before, "t1")]
                    == [("tool_call", "in_progress"), ("tool_call_update", "completed")]
                    and calls(before, "t1")[0].get("locations") == [{"path": os.path.join(one, "note.txt")}], calls(before, "t1")),
        agent.check("the write asks the client, with the screen's answers",
                    [(a["toolCall"]["toolCallId"], [o["optionId"] for o in a["options"]]) for a in client.asked]
                    == [("t2", ["once", "session", "deny"])], client.asked),
        agent.check("allowed once, it wrote in the session's folder and nowhere else",
                    os.path.exists(os.path.join(one, "made.txt")) and not os.path.exists(os.path.join(elsewhere, "made.txt"))
                    and calls(before, "t2")[-1].get("status") == "completed", (os.listdir(one), os.listdir(elsewhere))),
        agent.check("the session's file is the one its id names",
                    [os.path.basename(f) for f in files] == [session + ".jsonl"], files),
    ]
    client.choices = ["deny"]
    again, before = client.request("session/prompt", prompt(session, "And again?"))
    results += [
        agent.check("a write the client denies writes nothing, and the model is told",
                    not os.path.exists(os.path.join(one, "refused.txt")) and len(server.requests) == 5
                    and "did not allow" in json.dumps(server.requests[4]["body"]["messages"][-1])
                    and calls(before, "t3")[-1].get("status") == "failed",
                    (calls(before, "t3"), server.requests[-1]["body"]["messages"][-1])),
        agent.check("a second prompt is the next turn", again.get("result") == {"stopReason": "end_turn"}
                    and chunks(before, "agent_message_chunk", session) == "Second answer.", (again, before)),
        agent.check("it carries the first turn's history",
                    len(server.requests) == 5 and "What does note.txt say?" in json.dumps(server.requests[3]["body"]["messages"]),
                    len(server.requests)),
        agent.check("still one session file", len(agent.sessions(state)) == 1, agent.sessions(state)),
    ]

    print("B: a second session, in another folder")
    made, _ = client.request("session/new", {"cwd": two, "mcpServers": []})
    other = made.get("result", {}).get("sessionId", "")
    answer, before = client.request("session/prompt", prompt(other, "Hello?"))
    last = server.requests[-1]["body"]["messages"] if server.requests else []
    results += [
        agent.check("it has an id of its own", bool(other) and other != session, made),
        agent.check("its answer names it", chunks(before, "agent_message_chunk", other) == "Hello from two.", before),
        agent.check("its history is its own", len(last) == 1 and "note.txt" not in json.dumps(last), last),
        agent.check("each session has its file", sorted(os.path.basename(f) for f in agent.sessions(state))
                    == sorted([session + ".jsonl", other + ".jsonl"]), agent.sessions(state)),
        agent.check("a session nobody made is not found", client.request("session/prompt", prompt("nope", "x"))[0]
                    .get("error", {}).get("code") == -32002),
        agent.check("a folder that is not one makes no session",
                    "is not a folder" in client.request("session/new", {"cwd": os.path.join(root, "missing")})[0]
                    .get("error", {}).get("message", "")),
    ]

    print("C: the streams")
    status, said = client.close()
    results += [
        agent.check("every line on standard output is a protocol message", not client.not_json and all(
            json.loads(line).get("jsonrpc") == "2.0" for line in client.lines), client.not_json[:3]),
        agent.check("ask ends when its input does, with 0", status == 0, (status, said[-400:])),
    ]
    print("D: another ask loads the first session")
    client = Client(binary, elsewhere, agent.environment(state, server.url))
    opened, _ = client.request("initialize", {"protocolVersion": 1})
    loaded, replayed = client.request("session/load", {"sessionId": session, "cwd": one, "mcpServers": []})
    told = [u.get("sessionUpdate") for u in (m["params"]["update"] for m in replayed if m.get("method") == "session/update")]
    answer, before = client.request("session/prompt", prompt(session, "Go on."))
    last = server.requests[-1]["body"]["messages"]
    results += [
        agent.check("ask says it can load", opened.get("result", {}).get("agentCapabilities", {}).get("loadSession") is True, opened),
        agent.check("the load answers after the replay", loaded.get("result") == {} and len(replayed) > 0, loaded),
        agent.check("the prompts are replayed as the person's",
                    chunks(replayed, "user_message_chunk", session) == "What does note.txt say?And again?", replayed),
        agent.check("the answers are replayed as the model's",
                    chunks(replayed, "agent_message_chunk", session) == "Reading. It says: the note of one.Second answer.", replayed),
        agent.check("the calls are replayed with how they ended",
                    [calls(replayed, c)[-1].get("status") for c in ("t1", "t2", "t3")] == ["completed", "completed", "failed"],
                    [calls(replayed, c) for c in ("t1", "t2", "t3")]),
        agent.check("nothing is asked again, and the replay starts with the first prompt",
                    not client.asked and told[:1] == ["user_message_chunk"], (client.asked, told)),
        agent.check("the loaded session goes on with its history", answer.get("result") == {"stopReason": "end_turn"}
                    and chunks(before, "agent_message_chunk", session) == "Continued."
                    and "What does note.txt say?" in json.dumps(last) and last[-1]["content"][-1].get("text") == "Go on.", last[-1]),
        agent.check("it wrote to the same file", sorted(os.path.basename(f) for f in agent.sessions(state))
                    == sorted([session + ".jsonl", other + ".jsonl"]), agent.sessions(state)),
        agent.check("a session of another folder is not found there",
                    client.request("session/load", {"sessionId": other, "cwd": one})[0].get("error", {}).get("code") == -32002),
        agent.check("a name that is a path is not found", client.request(
            "session/load", {"sessionId": "../" + os.path.basename(os.path.dirname(agent.sessions(state)[0])) + "/" + other,
                             "cwd": one})[0].get("error", {}).get("code") == -32002),
    ]
    status, said = client.close()
    results.append(agent.check("it ends with 0 too", status == 0, (status, said[-300:])))
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
