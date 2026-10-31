#!/usr/bin/env python3
"""Changes made while a turn runs (roadmap 0113), through the real binary in a PTY: the turn's next request uses them.

A: a settings file edited while a tool runs: the next request of the same turn goes to the file's new model.
B: /model typed while a tool runs: accepted at once, and the next request of the same turn goes to the chosen model.
C: /thinking typed while a tool runs: accepted at once, and the next request asks for that effort.
D: /config show reads the settings while a turn runs, and /mcp reports, without stopping it.
E: the settings editor opens while a turn runs, and a value saved there applies to the turn's next request.
F: /compact typed while a turn runs waits, shown as waiting, and runs when the turn ends.
G: /new typed while a turn runs waits for the turn's end, then starts a new session.
H: /fork while a turn runs makes the copy at once and stays with the turn.
I: /skill:NAME typed while a turn runs reaches the model expanded, as at a turn's start.
J: /logout of the account in use waits for the turn's end.

    ASK_PYTE=/tmp/ask-pty/lib python3 Scripts/probe-mid-turn.py [.build/release/ask]
"""
import importlib.util, json, os, sys, tempfile, time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("interactive_probe", os.path.join(here, "probe-interactive.py"))
interactive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(interactive)
agent, Screen, check = interactive.agent, interactive.Screen, interactive.check
interactive.ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
SLOW = "sleep 4; echo slept"


CATALOG = [{"id": "claude-sonnet-4-5", "max_input_tokens": 200000, "max_tokens": 64000,
            "capabilities": {"thinking": {"supported": True, "types": {"enabled": {"supported": True}}},
                             "effort": {"low": {"supported": True}, "high": {"supported": True}}}}]


def started(config_text, more=(), skill=None):
    """A screen on a fresh project whose first prompt runs a slow tool, then answers; the configuration is `config_text`. `more` are
    the responses after those, and `skill` a SKILL.md body to install as the user's skill `demo`."""
    project, config = tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    if skill:
        os.makedirs(os.path.join(config, "ask", "skills", "demo"))
        open(os.path.join(config, "ask", "skills", "demo", "SKILL.md"), "w").write(
            "---\nname: demo\ndescription: A demo skill for the probe.\n---\n" + skill + "\n")
    path = os.path.join(config, "ask", "config.json")
    open(path, "w").write(config_text)
    server = agent.Server([agent.turn([("tool", "t1", SLOW)], "tool_use"), agent.turn([("text", "Answered after.")], "end_turn"),
                           *more], catalog=CATALOG)
    screen = Screen(server.url, project, config=config)
    screen.ready()
    screen.type("go\r")
    running = screen.until_status("working", 10)
    return screen, server, path, running


def second_request(server, screen):
    """The second request's body, once the turn ended."""
    screen.until("Answered after.", 20)
    screen.until_status("ready")
    return server.requests[1]["body"] if len(server.requests) >= 2 else {}


def finish(screen, server):
    screen.type("\x15/quit\r")
    code = screen.finish()
    server.httpd.shutdown()
    return code


def probe_file():
    print("A: a settings file edited while a tool runs applies to the turn's next request")
    screen, server, path, running = started(json.dumps({"model": "first-model", "provider": "anthropic"}))
    time.sleep(0.5)
    open(path, "w").write(json.dumps({"model": "edited-model", "provider": "anthropic"}))
    body = second_request(server, screen)
    results = [check("the turn was running", running),
               check("the first request used the first model", server.requests and server.requests[0]["body"]["model"] == "first-model"),
               check("the next request of the same turn used the edited model", body.get("model") == "edited-model", body.get("model")),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_model():
    print("B: /model while a tool runs is accepted at once and applies to the turn's next request")
    screen, server, _, running = started(json.dumps({"model": "first-model", "provider": "anthropic"}))
    screen.type("/model picked-model\r")
    accepted = screen.until("Model selected for this run: picked-model", 3)
    still = not screen.idle()
    interactive.dismiss_thinking_offer(screen)
    body = second_request(server, screen)
    results = [check("the turn was running", running),
               check("accepted while the tool ran", accepted and still, screen.screen.text()[-600:]),
               check("the next request of the same turn used it", body.get("model") == "picked-model", body.get("model")),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_thinking():
    print("C: /thinking while a tool runs applies to the turn's next request")
    screen, server, _, running = started(json.dumps({"model": "claude-sonnet-4-5", "provider": "anthropic"}))
    screen.type("/thinking high\r")
    accepted = screen.until("Thinking", 3) and not screen.idle()
    body = second_request(server, screen)
    first = server.requests[0]["body"].get("thinking") if server.requests else None
    results = [check("the turn was running", running),
               check("accepted while the tool ran", accepted, screen.screen.text()[-600:]),
               check("the next request asks for the new effort", body.get("thinking") not in (None, first), (first, body.get("thinking"))),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_reading():
    print("D: /config and /mcp answer while a turn runs, and the turn goes on")
    screen, server, _, running = started(json.dumps({"model": "first-model", "provider": "anthropic"}))
    screen.type("/config show\r")
    shown = screen.until("user file", 3) and not screen.idle()
    screen.type("/mcp\r")
    reported = screen.until("MCP", 3) and not screen.idle()
    body = second_request(server, screen)
    results = [check("the turn was running", running),
               check("/config answered during the turn", shown, screen.screen.text()[-600:]),
               check("/mcp answered during the turn", reported, screen.screen.text()[-600:]),
               check("the turn finished", body.get("model") == "first-model", body.get("model")),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_editor():
    print("E: the settings editor opens while a turn runs, and what it saves applies to the turn's next request")
    screen, server, path, running = started(json.dumps({"model": "claude-sonnet-4-5", "provider": "anthropic", "thinking": "low"}))
    screen.type("/config user\r")
    opened = screen.until("ui.tint", 3) and screen.until("Enter saves", 1)
    # The editor is drawn over the transcript; the turn's tool goes on under it. A value written to the file meanwhile, as the editor's
    # save does, applies to the next request like any change of the file.
    open(path, "w").write(json.dumps({"model": "claude-sonnet-4-5", "provider": "anthropic", "thinking": "high"}))
    time.sleep(0.5)
    screen.type("\x1b")
    body = second_request(server, screen)
    first = server.requests[0]["body"].get("thinking") if server.requests else None
    results = [check("the turn was running", running),
               check("the editor opened during the turn", opened, screen.screen.text()[-600:]),
               check("the next request asks for the saved effort", body.get("thinking") != first and body.get("thinking"), (first, body.get("thinking"))),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


PLAIN = json.dumps({"model": "first-model", "provider": "anthropic"})


def probe_compact():
    print("F: /compact while a turn runs waits for its end, then runs")
    screen, server, _, running = started(PLAIN, more=[agent.turn([("text", "A SUMMARY OF IT ALL")], "end_turn")])
    screen.type("/compact\r")
    waiting = screen.until("/compact", 3) and not screen.idle() and len(server.requests) == 1
    early = "compact · " in screen.screen.text()
    screen.until("Answered after.", 20)
    ran = screen.until("compact · ", 10)
    text = screen.screen.text()
    screen.until_status("ready")
    # This short session has nothing before its recent messages, so the compaction says so rather than asking for a summary: what is
    # probed is when it runs.
    results = [check("the turn was running", running),
               check("waiting while the turn runs, nothing sent for it", waiting and not early, screen.screen.text()[-600:]),
               check("run once the turn ended", ran and text.index("Answered after.") < text.index("compact · "), text[-600:]),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_new():
    print("G: /new while a turn runs waits for its end, then starts a new session")
    screen, server, _, running = started(PLAIN)
    screen.type("/new\r")
    early = "New session." in screen.screen.text()
    screen.until("Answered after.", 20)
    started_new = screen.until("New session. The previous one is saved.", 10)
    results = [check("the turn was running", running),
               check("not before the turn ended", not early),
               check("a new session once it ended", started_new, screen.screen.text()[-600:]),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_fork():
    print("H: /fork while a turn runs makes the copy at once and stays with the turn")
    screen, server, _, running = started(PLAIN)
    time.sleep(0.5)
    screen.type("/fork\r")
    forked = screen.until("Forked into session", 3) and not screen.idle()
    body = second_request(server, screen)
    results = [check("the turn was running", running),
               check("forked during the turn", forked, screen.screen.text()[-600:]),
               check("which went on and finished here", screen.screen.text().count("Answered after.") >= 1 and body.get("model") == "first-model"),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_skill():
    print("I: /skill:NAME typed while a turn runs reaches the model expanded")
    screen, server, _, running = started(PLAIN, skill="DEMO SKILL BODY: always answer in haiku.")
    screen.type("/skill:demo now in verse\r")
    second_request(server, screen)
    sent = json.dumps(server.requests[1]["body"]["messages"]) if len(server.requests) >= 2 else ""
    results = [check("the turn was running", running),
               check("the turn's next request carries the skill", "DEMO SKILL BODY" in sent, sent[-400:]),
               check("the screen shows the line as typed, not the skill", "DEMO SKILL BODY" not in screen.screen.text()),
               check("clean exit", finish(screen, server) == 0)]
    return all(results)


def probe_logout():
    print("J: /logout of the account in use waits for the turn's end")
    screen, server, _, running = started(PLAIN)
    screen.type("/logout claude\r")
    told = screen.until("when the running turn ends", 3) and not screen.idle()
    signed = "Signed out of" in screen.screen.text() or "Not signed out" in screen.screen.text()
    screen.until("Answered after.", 20)
    after = screen.until("igned out", 10)
    results = [check("the turn was running", running),
               check("said it waits, while the turn runs", told, screen.screen.text()[-600:]),
               check("did nothing before the turn ended", not signed),
               check("signed out once it ended", after, screen.screen.text()[-600:]),
               check("ask still runs and quits cleanly", finish(screen, server) == 0)]
    return all(results)


if __name__ == "__main__":
    ok = True
    for probe in (probe_file, probe_model, probe_thinking, probe_reading, probe_editor, probe_compact, probe_new, probe_fork,
                  probe_skill, probe_logout):
        ok = probe() and ok
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
