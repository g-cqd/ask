#!/usr/bin/env python3
"""Self-test of Scripts/land.py: a task worktree made from origin/main, as the workflow makes them, lands on local main end to end, and
its worktree and branch are removed. The gate is a stub; nothing is pushed."""
import os
import pathlib
import shutil
import subprocess
import tempfile

SCRIPTS = pathlib.Path(__file__).resolve().parent
EMAIL = "42325924+g-cqd@users.noreply.github.com"
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_COMMITTER_NAME="t", GIT_AUTHOR_EMAIL=EMAIL, GIT_COMMITTER_EMAIL=EMAIL,
           GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null", ASK_LAND_EMAIL=EMAIL)


def run(cwd, *args):
    return subprocess.run(args, cwd=cwd, env=ENV, capture_output=True, text=True)


def git(cwd, *args):
    result = run(cwd, "git", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main", *args)
    assert result.returncode == 0, (args, result.stderr)
    return result.stdout.strip()


with tempfile.TemporaryDirectory() as directory:
    top = pathlib.Path(directory).resolve()
    git(top, "init", "-q", "--bare", "origin.git")
    git(top, "clone", "-q", str(top / "origin.git"), "main")
    main = top / "main"
    (main / "Scripts").mkdir()
    for name in ["land.py", "record_numbers.py"]:
        shutil.copy(SCRIPTS / name, main / "Scripts" / name)
    (main / "Scripts" / "quality.sh").write_text("#!/bin/sh\nexit 0\n")
    (main / "Scripts" / "quality.sh").chmod(0o755)
    (main / ".gitignore").write_text("__pycache__/\n")
    git(main, "add", ".")
    git(main, "commit", "-q", "-m", "base")
    git(main, "push", "-q", "origin", "main")
    task = top / "task"
    git(main, "worktree", "add", "-q", "-b", "task", str(task), "origin/main")
    (task / "change.txt").write_text("x\n")
    git(task, "add", ".")
    git(task, "commit", "-q", "-m", "change")
    head = git(task, "rev-parse", "HEAD")
    landed = run(task, "python3", "-B", "Scripts/land.py")
    assert landed.returncode == 0, landed.stdout + landed.stderr
    assert git(main, "rev-parse", "main") == head, "main is fast-forwarded to the task"
    assert not task.exists(), "the task worktree is removed"
    assert git(main, "branch", "--list", "task") == "", "the task branch is removed"
    assert git(main, "rev-parse", "origin/main") != head, "nothing is pushed"
print("land self-test: ok")
