#!/usr/bin/env python3
"""A picture pasted into a prompt (roadmap 0224; the owner, 2026-11-12) through the real binary, a PTY and a local fake provider.

Scripts/probe-paste-image.py .build/release/ask

A PNG's path is pasted as a terminal pastes a dropped file (bracketed, with a blank after it): the input gets `[image 1]`, its
caption shows above the input, and the message sent carries the picture as an image block after its text. Resumed, the message
shows its caption again. The pasteboard's own pictures (Ctrl+V with a picture copied) are not probed: that needs the person's
pasteboard. Hermetic otherwise: a picture made here, no window or credentials.
"""
import base64
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_images", os.path.join(HERE, "probe-images.py"))
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)
probe = images.probe


def main():
    check = probe.check
    with tempfile.TemporaryDirectory() as root:
        project, config, state = os.path.realpath(root) + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        picture = images.png(3, 2)
        path = os.path.join(project, "shot one.png")
        with open(path, "wb") as file:
            file.write(picture)
        server = probe.agent.Server([probe.agent.turn([("text", "A SMALL PICTURE")], "end_turn")])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", LANG="en_US.UTF-8")
        caption = f"[image 1] PNG · 3×2 · {len(picture)} B"
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=110, rows=30)
            terminal.until(lambda: "ask>" in terminal.text())
            dropped = path.replace(" ", "\\ ") + " "
            terminal.send(b"\x1b[200~" + dropped.encode() + b"\x1b[201~")
            terminal.until(lambda: "ask> [image 1]" in terminal.text())
            check("a dropped picture's path becomes [image 1] in the input", True)
            check("and its caption shows above the input", caption in terminal.text())
            terminal.send(b" what is this?\r")
            terminal.until(lambda: "A SMALL PICTURE" in terminal.text())
            sent = server.requests[-1]["body"]["messages"][0]["content"]
            # The Claude subscription's wire carries the instructions first in the same message: the person's text is found by
            # its words.
            text = next(i for i, block in enumerate(sent) if block.get("text") == "[image 1] what is this?")
            check("the message sends its text, then the picture as an image block",
                  sent[text + 1].get("type") == "image"
                  and sent[text + 1]["source"]["data"] == base64.b64encode(picture).decode())
            check("the message shows its picture's caption under it", "PNG · 3×2" in terminal.text())
            terminal.send(b"/quit\r")
            terminal.close()
            terminal = probe.Terminal(project, environment, columns=110, rows=30, resume=True)
            terminal.until(lambda: "A SMALL PICTURE" in terminal.text())
            check("resumed, the message shows its picture's caption again", "PNG · 3×2" in terminal.text())
        except (AssertionError, StopIteration, ValueError, IndexError, KeyError):
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
