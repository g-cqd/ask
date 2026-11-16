#!/usr/bin/env python3
"""Roadmap 0234 step 2: `ask serve` speaks the Agent Client Protocol on its standard streams (ADR-0153), each session a
conversation of its own in the folder the client names (ADR-0154). Driven here over pipes, against the local fake model server,
from a working directory that is none of the sessions'.

A: one session: initialize, session/new, a prompt with two tool calls in it, a second prompt. The model's words arrive as chunks,
   in order, before the answer; each call is told as it begins and ends; the read was of the session's folder; the write asks the
   client, which allows the first and denies the second, and is told as a diff with the model's input; the session file is the
   one the id names. The session's commands are told after the answer that made it.
B: two sessions in two folders: each keeps its own file and its own history. The second is given an MCP server, which the
   model is offered there and not in the first, and which runs in the session's folder; one of a kind ask does not speak to
   costs the session nothing. A prompt that is a command (`/tasks`) is run by
   ask and answered without the model; one that names a skill reaches the model with the skill's text.
C: nothing but protocol messages on standard output, and ask ends when its input does.
E: a prompt whose command sleeps is cancelled: it answers `cancelled` at once, the command is gone, the session goes on; and a
   line that is not JSON is answered, with what follows it taken in its order.
H: the model asks a question: the client is asked for a form, and the model is told what the person chose.
J: a session loaded again by the connection that serves it is told again whole, as it is now, and goes on.
I: a command that goes on after its call has ended (a `bash` call that yielded) is told on that call as it prints, after
   the turn has ended, and then that it ended.
G: the client goes away while a command runs: ask stops the command and ends with 0, not killed by a pipe nobody reads.
F: a turn the provider refuses is answered with an error that says why, a client that shows notices is told as it happens,
   and the session takes the next prompt.
D: a second `ask serve` loads the first session: its prompts, answers and calls are replayed in order before the answer, and the
   next prompt continues it in the same file. Its client shows forms, so the model is offered the `question` tool there, which it
   was not for the first client, which shows none.

Scripts/probe-serve.py .build/release/ask
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
saved, sys.argv = sys.argv, sys.argv[:1]
spec.loader.exec_module(agent)
sys.argv = saved

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tests", "AskMCPTests", "Fixtures", "fixture-server.py")


class Client:
    """An ACP client over the pipes of one `ask serve`: a request, then every message read until its answer."""

    def __init__(self, binary, cwd, env):
        self.process = subprocess.Popen([binary, "serve"], cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
        self.next_id, self.lines, self.not_json = 1, [], []
        # The option chosen for each permission ask makes, in order; "once" when the list is used up.
        self.choices, self.asked = [], []
        # What a form is answered with (declined by default), and the forms ask asked for.
        self.form_answer, self.forms = {"action": "decline"}, []
        # Called with each message read while a request waits for its answer, and with this client.
        self.watch = None

    def request(self, method, params, until=None):
        """The answer to the request, and the notifications that came before it. With `until`, a test of each message read, it
        returns (None, messages) as soon as one passes, without waiting for the answer."""
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
            if self.watch:
                self.watch(parsed, self)
            if parsed.get("method") == "session/request_permission":
                self.asked.append(parsed["params"])
                chosen = self.choices.pop(0) if self.choices else "once"
                reply = {"jsonrpc": "2.0", "id": parsed["id"], "result": {"outcome": {"outcome": "selected", "optionId": chosen}}}
                self.process.stdin.write((json.dumps(reply) + "\n").encode())
                self.process.stdin.flush()
            if parsed.get("method") == "elicitation/create":
                self.forms.append(parsed["params"])
                reply = {"jsonrpc": "2.0", "id": parsed["id"], "result": self.form_answer}
                self.process.stdin.write((json.dumps(reply) + "\n").encode())
                self.process.stdin.flush()
            if until and until(parsed):
                return None, before

    def read_until(self, test, seconds):
        """The messages read until one passes `test`, which is the last; ask is killed when none does in `seconds`, and the
        last is then None."""
        guard = threading.Timer(seconds, self.process.kill)
        guard.start()
        read = []
        while True:
            line = self.process.stdout.readline()
            if not line:
                return read + [None]
            self.lines.append(line)
            read.append(json.loads(line))
            if test(read[-1]):
                guard.cancel()
                return read

    def notify(self, method, params):
        self.process.stdin.write((json.dumps({"jsonrpc": "2.0", "method": method, "params": params}) + "\n").encode())
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


def formless_tools(server, count):
    """The names of the tools offered in each of the first `count` requests: the first session's."""
    return [[tool["name"] for tool in request["body"].get("tools", [])] for request in server.requests[:count]]


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
        agent.turn([("text", "Demo done.")], "end_turn"),
        agent.turn([("call", "t20", "mcp__My-Fixture__pwd", {})], "tool_use"),
        agent.turn([("text", "It runs there.")], "end_turn"),
        agent.turn([("text", "Continued.")], "end_turn"),
        agent.turn([("call", "t9", "bash", {"command": "sleep 47.3"})], "tool_use"),
        agent.turn([("text", "After the cancel.")], "end_turn"),
        agent.sse([{"type": "error", "error": {"type": "permission_error", "message": "Your key may not use this model."}}]),
        agent.turn([("text", "After the failure.")], "end_turn"),
        agent.turn([("call", "t11", "question", {"questions": [
            {"question": "Which side?", "header": "Side", "choices": [{"label": "Left"}, {"label": "Right"}], "note": "none"}]})],
            "tool_use"),
        agent.turn([("text", "Right it is.")], "end_turn"),
        agent.turn([("call", "t12", "bash", {"command": "echo early-line; sleep 3; echo late-line", "yield_seconds": 1})],
                   "tool_use"),
        agent.turn([("text", "It goes on.")], "end_turn"),
        agent.turn([("call", "t10", "bash", {"command": "sleep 48.6"})], "tool_use"),
    ])
    state = os.path.join(root, "state")
    # One skill, and no other: ask's own directory only, so the machine's skills are not among the commands.
    os.makedirs(os.path.join(state, "config", "ask", "skills", "demo"))
    with open(os.path.join(state, "config", "ask", "config.json"), "w") as file:
        json.dump({"skills": {"sources": ["ask"]}}, file)
    with open(os.path.join(state, "config", "ask", "skills", "demo", "SKILL.md"), "w") as file:
        file.write("---\nname: demo\ndescription: Does the demo.\n---\n# demo\n\nDo the demo thing.\n")
    client = Client(binary, elsewhere, agent.environment(state, server.url))

    print("A: one session")
    opened, _ = client.request("initialize", {"protocolVersion": 1, "clientCapabilities": {}})
    made, _ = client.request("session/new", {"cwd": one, "mcpServers": []})
    session = made.get("result", {}).get("sessionId", "")
    answer, before = client.request("session/prompt", prompt(session, "What does note.txt say?"))
    files = agent.sessions(state)
    commands = before[0].get("params", {}).get("update", {}) if before else {}
    made_diff = {"type": "diff", "path": os.path.join(one, "made.txt"), "newText": "made by serve\n"}
    results = [
        agent.check("initialize answers version 1", opened.get("result", {}).get("protocolVersion") == 1, opened),
        agent.check("session/new answers an id", bool(session), made),
        agent.check("the session's commands are told after that answer: the ones served, and the skill",
                    before[0].get("params", {}).get("sessionId") == session
                    and commands.get("sessionUpdate") == "available_commands_update"
                    and [c["name"] for c in commands.get("availableCommands", [])] == ["compact", "tasks", "skill:demo"],
                    before[:1]),
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
        agent.check("the write is told with the model's input and as a diff of the file, which it keeps when it ends",
                    calls(before, "t2")[0].get("rawInput") == {"path": "made.txt", "content": "made by serve\n"}
                    and calls(before, "t2")[0].get("content") == [made_diff] and calls(before, "t2")[-1]["content"][0] == made_diff,
                    calls(before, "t2")),
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
    # Its own MCP servers: one ask starts, named as a person would name it, and one of a kind ask does not speak to.
    given = [{"name": "My Fixture", "command": sys.executable, "args": [FIXTURE], "env": [{"name": "GIVEN", "value": "1"}]},
             {"type": "sse", "name": "old", "url": "http://127.0.0.1:9/sse", "headers": []}]
    made, _ = client.request("session/new", {"cwd": two, "mcpServers": given})
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

    asked = len(server.requests)
    listed, said = client.request("session/prompt", prompt(other, "/tasks"))
    unasked = len(server.requests)
    skilled, _ = client.request("session/prompt", prompt(other, "/skill:demo show it"))
    results += [
        agent.check("a command typed as a prompt is run by ask, answered with what it says, and the model is not asked",
                    listed.get("result") == {"stopReason": "end_turn"} and unasked == asked
                    and chunks(said, "agent_message_chunk", other).strip() != "",
                    (listed, unasked - asked, chunks(said, "agent_message_chunk", other))),
        agent.check("a skill typed as a prompt reaches the model with the skill's text",
                    skilled.get("result") == {"stopReason": "end_turn"} and len(server.requests) == asked + 1
                    and "Do the demo thing." in json.dumps(server.requests[-1]["body"]["messages"][-1])
                    and "show it" in json.dumps(server.requests[-1]["body"]["messages"][-1]),
                    (skilled, server.requests[-1]["body"]["messages"][-1])),
    ]

    there, _ = client.request("session/prompt", prompt(other, "Where does it run?"))
    offered = [tool["name"] for tool in server.requests[-1]["body"].get("tools", [])]
    results += [
        agent.check("ask says it speaks to a session's servers over HTTP",
                    opened.get("result", {}).get("agentCapabilities", {}).get("mcpCapabilities") == {"http": True}, opened),
        agent.check("the session has the server its client gave it, which the first session has not, and it runs in the session's folder",
                    there.get("result") == {"stopReason": "end_turn"} and "mcp__My-Fixture__pwd" in offered
                    and not any("mcp__" in name for names in formless_tools(server, 5) for name in names)
                    and two in json.dumps(server.requests[-1]["body"]["messages"][-1]),
                    (there, [name for name in offered if "mcp__" in name], server.requests[-1]["body"]["messages"][-1])),
    ]

    listed = subprocess.run([binary, "--help"], capture_output=True, text=True).stdout
    results.append(agent.check("`ask --help` lists serve", any(line.split()[:1] == ["serve"] for line in listed.splitlines()),
                               listed[-600:]))

    print("C: the streams")
    status, said = client.close()
    results += [
        agent.check("every line on standard output is a protocol message", not client.not_json and all(
            json.loads(line).get("jsonrpc") == "2.0" for line in client.lines), client.not_json[:3]),
        agent.check("ask ends when its input does, with 0", status == 0, (status, said[-400:])),
    ]
    print("D: another ask loads the first session")
    formless = [[tool["name"] for tool in r["body"].get("tools", [])] for r in server.requests]
    client = Client(binary, elsewhere, agent.environment(state, server.url))
    shows = {"session": {"notices": {}, "compaction": {}}, "elicitation": {"form": {}}}
    opened, _ = client.request("initialize", {"protocolVersion": 1, "clientCapabilities": shows})
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
        agent.check("its commands are told after what it holds", told[-1:] == ["available_commands_update"], told[-3:]),
        agent.check("the loaded session goes on with its history", answer.get("result") == {"stopReason": "end_turn"}
                    and chunks(before, "agent_message_chunk", session) == "Continued."
                    and "What does note.txt say?" in json.dumps(last) and last[-1]["content"][-1].get("text") == "Go on.", last[-1]),
        agent.check("the model was offered the question tool for this client, which shows forms, and not for the first, which shows none",
                    "question" in [tool["name"] for tool in server.requests[-1]["body"].get("tools", [])]
                    and len(formless) >= 4 and all("read" in names and "question" not in names for names in formless),
                    (len(formless), [names for names in formless if "question" in names or "read" not in names][:1],
                     [tool["name"] for tool in server.requests[-1]["body"].get("tools", [])])),
        agent.check("it wrote to the same file", sorted(os.path.basename(f) for f in agent.sessions(state))
                    == sorted([session + ".jsonl", other + ".jsonl"]), agent.sessions(state)),
        agent.check("a session of another folder is not found there",
                    client.request("session/load", {"sessionId": other, "cwd": one})[0].get("error", {}).get("code") == -32002),
        agent.check("a name that is a path is not found", client.request(
            "session/load", {"sessionId": "../" + os.path.basename(os.path.dirname(agent.sessions(state)[0])) + "/" + other,
                             "cwd": one})[0].get("error", {}).get("code") == -32002),
    ]
    print("E: a turn is cancelled while its command runs")

    def cancel_once_it_runs(message, client):
        update = message.get("params", {}).get("update", {})
        if update.get("toolCallId") == "t9" and update.get("sessionUpdate") == "tool_call_update" and "title" in update:
            client.watch = None
            client.notify("session/cancel", {"sessionId": session})

    client.watch = cancel_once_it_runs
    started = time.monotonic()
    answer, before = client.request("session/prompt", prompt(session, "Wait a while."))
    took = time.monotonic() - started
    sleeping = subprocess.run(["pgrep", "-f", "sleep 47.3"], capture_output=True, text=True).stdout.split()
    after, said_after = client.request("session/prompt", prompt(session, "And now?"))
    results += [
        agent.check("the prompt answers cancelled, not an error, and long before the command would have ended",
                    answer.get("result") == {"stopReason": "cancelled"} and took < 20, (answer, round(took, 1))),
        agent.check("the command was told as running, and is gone", any(u.get("status") == "in_progress" for u in calls(before, "t9"))
                    and not sleeping, (calls(before, "t9"), sleeping)),
        agent.check("the session takes the next prompt", after.get("result") == {"stopReason": "end_turn"}
                    and chunks(said_after, "agent_message_chunk", session) == "After the cancel.", (after, said_after)),
    ]
    print("F: a turn the provider refuses")
    failed, before = client.request("session/prompt", prompt(session, "Fail."))
    notices = [m["params"]["update"] for m in before
               if m.get("method") == "session/update" and m["params"]["update"].get("sessionUpdate") == "notice"]
    again, said_again = client.request("session/prompt", prompt(session, "Still there?"))
    results += [
        agent.check("the prompt is answered with an error that says why", failed.get("error", {}).get("code") == -32603
                    and "may not use this model" in failed["error"].get("message", ""), failed),
        agent.check("and a client that shows notices was told as it happened", any(
            n.get("severity") == "error" and "may not use this model" in n.get("title", "") + n.get("description", "")
            for n in notices), notices),
        agent.check("the session goes on", again.get("result") == {"stopReason": "end_turn"}
                    and chunks(said_again, "agent_message_chunk", session) == "After the failure.", (again, said_again)),
    ]
    print("H: the model asks the person a question")
    client.form_answer = {"action": "accept", "content": {"q1": "Right"}}
    asked, said_asked = client.request("session/prompt", prompt(session, "Ask me."))
    told = json.dumps(server.requests[-1]["body"]["messages"][-1])
    results += [
        agent.check("the client is asked for a form, about the question's call, with the choices by their words",
                    [(f.get("mode"), f.get("toolCallId"), f.get("message"),
                      [o["const"] for o in f["requestedSchema"]["properties"]["q1"]["oneOf"]]) for f in client.forms]
                    == [("form", "t11", "Which side?", ["Left", "Right"])], client.forms),
        agent.check("the model is told what the person chose", "Right" in told and "Left" not in told, told[:400]),
        agent.check("and the turn goes on", asked.get("result") == {"stopReason": "end_turn"}
                    and chunks(said_asked, "agent_message_chunk", session) == "Right it is.", (asked, said_asked)),
    ]
    garbage = Client(binary, elsewhere, agent.environment(state, server.url))
    garbage.process.stdin.write(b'this is not JSON\n{"jsonrpc":"2.0","id":5,"method":"session/new","params":{"cwd":"/"}}\n'
                                b'{"jsonrpc":"2.0","id":6,"method":"initialize","params":{"protocolVersion":1}}\n')
    garbage.process.stdin.flush()
    answers = [json.loads(garbage.process.stdout.readline()) for _ in range(3)]
    results += [
        agent.check("a line that is not JSON is answered with a parse error", answers[0].get("error", {}).get("code") == -32700, answers[0]),
        agent.check("what one write holds is taken in its order: the request before initialize is refused, initialize answered",
                    sorted((a.get("id"), a.get("error", {}).get("code")) for a in answers[1:]) == [(5, -32600), (6, None)], answers[1:]),
    ]
    garbage.close()

    print("I: a command goes on after its call has ended")

    def of_the_job(message):
        update = (message or {}).get("params", {}).get("update", {})
        return json.dumps(update.get("content", "")) if update.get("toolCallId") == "t12" else ""

    went_on, said_going = client.request("session/prompt", prompt(session, "Start it."))
    later = client.read_until(lambda message: "late-line" in of_the_job(message), 30)
    ended = later if "] ended" in of_the_job(later[-1]) else later + client.read_until(lambda m: "] ended" in of_the_job(m), 30)
    last = (ended[-1] or {}).get("params", {}).get("update", {})
    results += [
        agent.check("the turn ends while the command runs, its call completed, with what it had printed by then",
                    went_on.get("result") == {"stopReason": "end_turn"} and "completed" in [
                        update.get("status") for update in calls(said_going, "t12")]
                    and not any("late-line" in of_the_job(m) for m in said_going), (went_on, calls(said_going, "t12"))),
        agent.check("what it prints after the turn is told on its call, between turns, and then that it ended",
                    later[-1] is not None and ended[-1] is not None and "early-line" in of_the_job(ended[-1])
                    and "status" not in last and last.get("sessionUpdate") == "tool_call_update", (later[-3:], ended[-2:])),
    ]

    print("J: the session, loaded again by the connection that serves it")
    again, told_again = client.request("session/load", {"sessionId": session, "cwd": one, "mcpServers": []})
    said_again = json.dumps([m["params"]["update"] for m in told_again if m.get("method") == "session/update"])
    results.append(agent.check("it is told again whole, what this connection added with it, and stays the one it was",
                               again.get("result") == {} and "user_message_chunk" in said_again and "Start it." in said_again
                               and "late-line" in said_again, (again, said_again[-500:])))

    print("G: the client goes away while a command runs")

    def runs(message):
        update = message.get("params", {}).get("update", {})
        return update.get("toolCallId") == "t10" and update.get("sessionUpdate") == "tool_call_update" and "title" in update

    client.request("session/prompt", prompt(session, "Wait again."), until=runs)
    # The client dies: both its ends of the pipes close, with the command running and its answer still owed.
    client.process.stdin.close()
    client.process.stdout.close()
    try:
        status = client.process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        client.process.kill()
        status = "still running 20 s after its client had gone"
    sleeping = subprocess.run(["pgrep", "-f", "sleep 48.6"], capture_output=True, text=True).stdout.split()
    results += [
        agent.check("ask ends by itself, with 0, and not killed by the pipe it could no longer write to", status == 0,
                    (status, client.process.stderr.read().decode()[-300:])),
        agent.check("the command it ran for that client is gone with it", not sleeping, sleeping),
    ]
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
