#!/usr/bin/env python3
"""Land this clean task worktree on local main, after integration and the full quality gate. Never push."""
import argparse
import os
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True

from record_numbers import disk_paths, duplicates, git, prune_claims, records, tree_paths, worktrees


def clean(root):
    if git(root, "status", "--porcelain").stdout:
        raise RuntimeError("worktree is not clean: " + str(root))


def oid(root, ref):
    return git(root, "rev-parse", "--verify", ref).stdout.strip()


PUBLIC_EMAIL = "42325924+g-cqd@users.noreply.github.com"


def foreign_authors(root):
    """Commits on the task branch not yet on origin/main whose author or committer is not the public identity."""
    log = git(root, "log", "--format=%h %ae %ce", "origin/main..HEAD").stdout.splitlines()
    return [line for line in log if any(email != PUBLIC_EMAIL for email in line.split()[1:])]


def gaps(paths):
    days = {}
    for kind, day, number in records(paths):
        if kind == "diary":
            days.setdefault(day, set()).add(number)
    return {(day, n) for day, numbers in days.items() for n in range(1, max(numbers)) if n not in numbers}


def validate(root, baseline):
    paths = disk_paths(root)
    problems = duplicates(paths)
    added_gaps = gaps(paths) - gaps(baseline)
    problems += [f"new diary gap: {day}-{n:02d}" for day, n in sorted(added_gaps)]
    if problems:
        raise RuntimeError("\n".join(problems))


def land(root, keep):
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    if branch.returncode or branch.stdout.strip() == "main":
        raise RuntimeError("run from a named task branch, not main or detached HEAD")
    name = branch.stdout.strip()
    candidates = [pathlib.Path(p) for p in worktrees(root)
                  if git(p, "symbolic-ref", "--quiet", "HEAD", check=False).stdout.strip() == "refs/heads/main"]
    if len(candidates) != 1:
        raise RuntimeError("exactly one worktree must have main checked out")
    main = candidates[0]
    clean(root)
    clean(main)
    common = pathlib.Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
    lock = common / "ask-land.lock"
    try:
        lock.mkdir()
    except FileExistsError:
        raise RuntimeError("another landing holds " + str(lock) + "; inspect its owner before removing a stale lock") from None
    try:
        (lock / "owner").write_text(f"pid={os.getpid()}\nworktree={root}\nbranch={name}\n")
        subprocess.run(["git", "-C", str(root), "fetch", "origin"], check=True)
        original_main = oid(root, "main")
        original_remote = oid(root, "origin/main")
        baseline = tree_paths(root, "main") + tree_paths(root, "origin/main")
        # Validate only the merged tree: a branch that is merely behind main has gaps that the merge fills.
        for ref in ["main", "origin/main"]:
            subprocess.run(["git", "-C", str(root), "merge", "--no-edit", ref], check=True)
        validate(root, set(baseline))
        foreign = foreign_authors(root)
        if foreign:
            raise RuntimeError("commits not authored and committed as " + PUBLIC_EMAIL + ":\n" + "\n".join(foreign))
        desired = oid(root, "HEAD")
        print("==> full quality gate", flush=True)
        subprocess.run([str(root / "Scripts" / "quality.sh"), "--check"], cwd=root, check=True)
        clean(root)
        if oid(root, "HEAD") != desired:
            raise RuntimeError("task branch moved during the gate; rerun landing")
        # Fetch again: a moving remote invalidates the integration that was gated.
        subprocess.run(["git", "-C", str(root), "fetch", "origin"], check=True)
        if oid(root, "origin/main") != original_remote or oid(root, "main") != original_main:
            raise RuntimeError("main or origin/main moved during the gate; rerun landing")
        clean(main)
        if git(main, "symbolic-ref", "--quiet", "HEAD").stdout.strip() != "refs/heads/main":
            raise RuntimeError("main checkout changed branches during the gate")
        subprocess.run(["git", "-C", str(main), "merge", "--ff-only", desired], check=True)
        prune_claims(root)  # Only published records release claims, never an unpublished local landing.
        if not keep:
            os.chdir(main)
            subprocess.run(["git", "-C", str(main), "worktree", "remove", str(root)], check=True)
            subprocess.run(["git", "-C", str(main), "branch", "-d", name], check=True)
        print("Landed on local main. Nothing pushed." + (" Task worktree kept." if keep else ""))
    finally:
        (lock / "owner").unlink(missing_ok=True)
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="keep this task's worktree and branch after landing")
    args = parser.parse_args()
    try:
        root = pathlib.Path(git(".", "rev-parse", "--show-toplevel").stdout.strip()).resolve()
        land(root, args.keep)
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print("land: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
