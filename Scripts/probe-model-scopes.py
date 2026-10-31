#!/usr/bin/env python3
"""Roadmap 0094 on the real binary: a `modelScopes` rule in your own file limits which providers serve a repository.

    ASK_PYTE=/tmp/ask-pty/lib python3 Scripts/probe-model-scopes.py [.build/release/ask]

A fake Anthropic server, synthetic Codex credentials and cached model lists in temporary directories: nothing leaves the machine.
Each refusal has a control run, the same but with the rule pointing elsewhere, that must go through, so a probe that cannot fail
does not pass.
"""
import importlib.util, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    module = importlib.util.module_from_spec(spec)
    saved, sys.argv = sys.argv, [sys.argv[0]]
    spec.loader.exec_module(module)
    sys.argv = saved
    return module


picker = load("picker_probe", "probe-picker.py")
accounts = load("accounts_probe", "probe-model-accounts.py")
agent = picker.probe.agent


def check(label, condition, detail=""):
    if not condition:
        print("DETAIL", detail, file=sys.stderr)
    picker.check(label, condition)


def scoped(path, providers):
    return {"modelScopes": [{"path": "/nowhere", "providers": ["nobody"]}, {"path": path, "providers": providers}]}


def run(binary, arguments, rule_path):
    """`ask ARGUMENTS` in a fresh project whose user file holds a rule for `rule_path` (the project when None)."""
    root = tempfile.mkdtemp()
    project, state, config = root + "/project", root + "/state", root + "/config"
    for directory in (project, config + "/ask"):
        os.makedirs(directory)
    project = os.path.realpath(project)
    with open(config + "/ask/config.json", "w") as file:
        json.dump(scoped(rule_path or project, ["codex"]), file)
    server = agent.Server([agent.turn([("text", "Fine.")], "end_turn")])
    try:
        done = subprocess.run([binary] + arguments, cwd=project, env=agent.environment(state, server.url, config=config),
                              capture_output=True, text=True, timeout=60)
        return done, len(server.requests)
    finally:
        server.httpd.shutdown()
        server.httpd.server_close()


def commands(binary):
    print("A: commands")
    refusal = "anthropic is not allowed here: modelScopes rule 2 (path "
    done, requests = run(binary, ["-p", "hi", "--provider", "anthropic"], None)
    check("--provider outside the rule is refused before any request",
                 done.returncode == 78 and refusal in done.stderr and requests == 0, (done.returncode, done.stderr, requests))
    check("the refusal says what is allowed", "allows only codex. Choose one of them with --provider or /model."
                 in done.stderr, done.stderr)
    done, requests = run(binary, ["-p", "hi", "--provider", "anthropic"], "/elsewhere")
    check("control: the same run outside the rule is answered", done.returncode == 0 and requests == 1,
                 (done.returncode, done.stderr))
    done, _ = run(binary, ["models", "anthropic"], None)
    check("ask models refuses a provider outside the rule", done.returncode == 78 and refusal in done.stderr,
                 (done.returncode, done.stderr))
    done, _ = run(binary, ["models", "claude"], None)
    check("and its other name", done.returncode == 78 and refusal in done.stderr, (done.returncode, done.stderr))


def text(terminal):
    return "\n".join(picker.rows(terminal))


def picker_session(binary, inside):
    """/model with the Codex accounts of the accounts probe and a rule allowing them, inside the rule or not."""
    settings = (lambda project: scoped(project if inside else "/elsewhere", ["codex", "codex-2"]))
    with picker.Session(binary, [], prepare=accounts.prepare, settings=settings) as session:
        terminal = session.terminal
        terminal.until(lambda: "✓ ·" in terminal.text())
        status = next(row for row in picker.rows(terminal) if "✓ ·" in row)
        picker.type_text(terminal, "/model ")
        terminal.until(lambda: "codex/gpt-6-mini" in text(terminal))
        shown = text(terminal)
        for _ in range(len("/model ")):
            picker.press(terminal, b"\x7f")
        picker.type_text(terminal, "/model anthropic claude-sonnet-4-5")
        picker.press(terminal, b"\x1b")
        picker.press(terminal, b"\r")
        terminal.until(lambda: "Model not changed" in terminal.text() or "Model selected" in terminal.text())
        return status, shown, terminal.text()


def tui(binary):
    print("B: /model")
    status, shown, screen = picker_session(binary, inside=True)
    check("the default your files chose gives way to the rule's first provider", "✓ · codex/" in status, status)
    check("the list holds the allowed accounts' models", "codex/gpt-6-mini" in shown, shown)
    check("and nothing of a provider the rule leaves out", "anthropic" not in shown, shown)
    check("/model naming one is refused with the rule",
                 "Model not changed" in screen and "not allowed here: modelScopes rule 2" in screen, screen[-600:])
    status, shown, screen = picker_session(binary, inside=False)
    check("control: outside the rule the default stays", "codex/" not in status, status)
    check("control: outside the rule anthropic is listed", "anthropic" in shown, shown)
    check("control: and /model may choose it", "Model selected" in screen, screen[-600:])


def main():
    binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
    commands(binary)
    tui(binary)
    print("PASS", len(picker.checks), "checks")


if __name__ == "__main__":
    main()
