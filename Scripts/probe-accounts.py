#!/usr/bin/env python3
"""End-to-end probe of /model, /thinking, /login and /logout over a PTY (ADR-0117), against a private copy of the credentials.

A: only Codex is signed in, nothing names a provider: the screen opens on Codex, /model lists models and a choice is in force at once, and the
   effort list that opens after it takes a choice too.
B: /login claude api-key asks for the key in the status line, the key is stored, it is in neither the transcript nor the screen, and ask is still running.
C: Esc cancels a question; /logout lists the accounts and signs one out without leaving.
D: /login with the wrong words says so and stays.

Usage: Scripts/probe-accounts.py .build/release/ask [CONFIG_DIR_TO_COPY]
"""
import importlib.util, json, os, shutil, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("interactive", os.path.join(here, "probe-interactive.py"))
interactive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(interactive)
ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
SOURCE = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.config/ask")
SECRET = "sk-ant-PROBE-SECRET-0123456789"


class Session(interactive.Screen):
    """The interactive screen with a private config directory and no network key in the environment."""

    def __init__(self, project, config_home):
        self.state = tempfile.mkdtemp()
        env = {"PATH": os.environ["PATH"], "HOME": self.state, "XDG_CONFIG_HOME": config_home, "XDG_STATE_HOME": self.state,
               "TERM": "xterm-256color"}
        env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
        import pty, fcntl, struct, termios
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(project)
            os.execve(ASK, [ASK], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", interactive.ROWS, interactive.COLUMNS, 0, 0))
        self.output = b""
        self.screen = interactive.Emulator()


def config(copy=True):
    home = tempfile.mkdtemp()
    if copy and os.path.isdir(SOURCE):
        shutil.copytree(SOURCE, os.path.join(home, "ask"))
        for name in os.listdir(os.path.join(home, "ask")):
            if name.endswith(".lock"):
                os.unlink(os.path.join(home, "ask", name))
    else:
        os.makedirs(os.path.join(home, "ask"), mode=0o700)
    return home


def keys(session, text, settle=0.3):
    session.type(text)
    session.until("\x00", settle)


def idle(session):
    """Waits until the screen has been quiet and the status line says ready, so the next keys meet an idle prompt."""
    session.until("\x00", 0.6)
    session.until_status("ready")
    session.until("\x00", 0.3)


def probe_models():
    print("A: /model lists, a choice is in force at once, and the effort list follows")
    home = config()
    session = Session(tempfile.mkdtemp(), home)
    results = [interactive.check("opens on codex with nothing named", session.until("codex/"))]
    session.type("/model ")
    results.append(interactive.check("the model list opens", session.until("gpt-6-astra")))
    session.type("astra")
    session.until("\x00", 0.5)
    results.append(interactive.check("typing narrows it", "gpt-6-sol" not in session.screen.text() and "gpt-6-astra" in session.screen.text()))
    session.type("\r")
    results.append(interactive.check("the choice is in force at once", session.until("Model selected for this run: gpt-6-astra")))
    results.append(interactive.check("the effort list opens by itself", session.until("effort") or session.until("xhigh")))
    keys(session, "\x1b[B")
    session.type("\r")
    results.append(interactive.check("an effort is chosen", session.until("Thinking set to")))
    results.append(interactive.check("the label follows", session.until_status("astra")))
    session.type("\x03\x03")
    results.append(interactive.check("quits cleanly", session.finish() == 0))
    return all(results)


def probe_login():
    print("B: /login claude api-key keeps the key out of the screen, and stays")
    home = config(copy=False)
    session = Session(tempfile.mkdtemp(), home)
    session.until("ask>")
    session.type("/login claude api-key\r")
    results = [interactive.check("the key is asked for", session.until("Enter sends"))]
    session.type(SECRET)
    session.until("\x00", 0.5)
    results.append(interactive.check("typed as dots, never as text", SECRET not in session.screen.text() and "•" in session.screen.text()))
    session.type("\r")
    results.append(interactive.check("stored, and said", session.until("API key stored for anthropic")))
    results.append(interactive.check("the key is nowhere on screen", SECRET not in session.output.decode(errors="replace")))
    stored = json.load(open(os.path.join(home, "ask", "credentials.json")))
    results.append(interactive.check("the key is in the credential file", stored["keys"]["anthropic"]["key"] == SECRET))
    sessions = []
    for root, _, files in os.walk(session.state):
        sessions += [os.path.join(root, f) for f in files if f.endswith(".jsonl")]
    results.append(interactive.check("no session file holds it", not any(SECRET in open(p).read() for p in sessions)))
    idle(session)
    results.append(interactive.check("the model list opens for the new account", session.until("/model")))
    for _ in range(3):
        keys(session, "\x03", 0.7)
    code = session.finish()
    results.append(interactive.check("ask was still running, and quits cleanly", code == 0, code))
    return all(results)


def probe_cancel_and_logout():
    print("C: Esc cancels a question; /logout signs out without leaving")
    home = config(copy=False)
    session = Session(tempfile.mkdtemp(), home)
    session.until("ask>")
    session.type("/login claude api-key\r")
    session.until("Enter sends")
    session.type("\x1b")
    results = [interactive.check("Esc cancels, and it is not a failure", session.until("Sign-in cancelled."))]
    idle(session)
    session.type("/login claude api-key\r")
    session.until("Enter sends")
    session.type(SECRET + "\r")
    session.until("API key stored")
    idle(session)
    keys(session, "\x03")
    session.type("/logout ")
    results.append(interactive.check("the accounts are listed", session.until("every account ask has stored")))
    session.until("\x00", 0.5)
    session.type("\r")
    results.append(interactive.check("signed out, in the conversation", session.until("Signed out of claude")))
    stored = json.load(open(os.path.join(home, "ask", "credentials.json"))) if os.path.exists(os.path.join(home, "ask", "credentials.json")) else {}
    results.append(interactive.check("the key is gone", "anthropic" not in (stored.get("keys") or {})))
    idle(session)
    keys(session, "\x03", 0.7)
    keys(session, "\x03", 0.7)
    results.append(interactive.check("still there, quits cleanly", session.finish() == 0))
    return all(results)


def probe_wrong_words():
    print("D: /login with wrong words says so and stays")
    session = Session(tempfile.mkdtemp(), config(copy=False))
    session.until("ask>")
    session.type("/login nonsense\r")
    results = [interactive.check("says no", session.until("no sign-in called"))]
    session.type("\x03\x03")
    results.append(interactive.check("quits cleanly", session.finish() == 0))
    return all(results)


if __name__ == "__main__":
    ok = [probe_models(), probe_login(), probe_cancel_and_logout(), probe_wrong_words()]
    sys.exit(0 if all(ok) else 1)
