#!/usr/bin/env python3
"""`!` and `!!` (note n56) through the real binary, a scripted provider and a PTY.

Scripts/probe-shell-line.py .build/release/ask

`!echo …` shows its block with the output, asks the model nothing, and its result goes with the next message; `!!printf …` sends the
command and its output to the model at once. The build before sends `!echo …` to the model as a message.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def last_user_text(request):
    messages = request["body"]["messages"]
    content = messages[-1]["content"]
    return content if isinstance(content, str) else "".join(b.get("text", "") for b in content)


def main():
    check = folding.check
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "tint": "off", "separator": "off", "padding": "off"}}, file)
        server = agent.Server([agent.turn([("text", "First answer.")], "end_turn"),
                               agent.turn([("text", "Second answer.")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8", SHELL="/bin/zsh")
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=110)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"!echo hello-from-$0\r")
            # Its output, not the header, which holds the command: `hello-from-/bin/zsh` is what $0 prints.
            terminal.until(lambda: "hello-from-/" in terminal.text() or "[exit" in terminal.text())
            text = terminal.text()
            check("! runs in the person's shell and shows its output, open", "hello-from-/bin/zsh" in text)
            check("! asks the model nothing", len(server.requests) == 0)
            terminal.send(b"and now?\r")
            terminal.until(lambda: "First answer." in terminal.text())
            sent = last_user_text(server.requests[0])
            check("its result goes with the next message, verbatim",
                  "I ran this in my shell:" in sent and "$ echo hello-from-$0" in sent and "hello-from-/bin/zsh" in sent
                  and sent.rstrip().endswith("and now?"))
            terminal.send(b"!!printf bang\r")
            terminal.until(lambda: "Second answer." in terminal.text())
            sent = last_user_text(server.requests[1])
            check("!! sends the command and its output at once, and the model answers",
                  "$ printf bang" in sent and "bang" in sent and "First answer." not in sent)
            check("and the result went once: the first one is not sent again", "hello-from-" not in sent)
        except (AssertionError, StopIteration, ValueError, IndexError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
