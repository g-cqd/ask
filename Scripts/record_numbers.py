"""ask's documentation numbering shared by claims, landing, and the quality gate."""
import os
import pathlib
import re
import subprocess

PATTERNS = {
    "adr": re.compile(r"docs/adr/(\d+)-[^/]+\.md$"),
    "roadmap": re.compile(r"docs/roadmap/(\d+)-[^/]+\.md$"),
    "diary": re.compile(r"docs/diary/(\d{4}-\d{2}-\d{2})-(\d+)\.md$"),
}


def git(root, *args, check=True):
    p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    if check and p.returncode:
        raise RuntimeError(p.stderr.strip() or "git command failed: " + " ".join(args))
    return p


def records(paths):
    result = {}
    for path in paths:
        for kind, pattern in PATTERNS.items():
            match = pattern.fullmatch(path)
            if match:
                groups = match.groups()
                key = (kind, groups[0] if kind == "diary" else "", int(groups[-1]))
                result.setdefault(key, []).append(path)
    return result


def tree_paths(root, ref):
    return git(root, "ls-tree", "-r", "--name-only", ref, "--", "docs/adr", "docs/roadmap", "docs/diary").stdout.splitlines()


def disk_paths(root):
    root = pathlib.Path(root)
    return [p.relative_to(root).as_posix() for kind in PATTERNS for p in (root / "docs" / kind).glob("*.md")]


def duplicates(paths):
    return [f"duplicate {kind} {day + ' ' if day else ''}{number}: " + ", ".join(names)
            for (kind, day, number), names in records(paths).items() if len(names) > 1]


def worktrees(root):
    # -z preserves spaces and newlines in paths; no shell interpolation.
    raw = subprocess.run(["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"], capture_output=True, check=True).stdout
    return [os.fsdecode(part[len(b"worktree "):]) for part in raw.split(b"\0") if part.startswith(b"worktree ")]


def claims(root):
    result = []
    for line in git(root, "for-each-ref", "--format=%(refname) %(objectname)", "refs/claims/").stdout.splitlines():
        ref, oid = line.split()
        tail = ref.removeprefix("refs/claims/")
        for kind in PATTERNS:
            pattern = r"diary-(\d{4}-\d{2}-\d{2})-(\d+)" if kind == "diary" else kind + r"-(\d+)"
            match = re.fullmatch(pattern, tail)
            if match:
                result.append(((kind, match[1] if kind == "diary" else "", int(match.groups()[-1])), ref, oid))
    return result


def prune_claims(root):
    if git(root, "rev-parse", "--verify", "origin/main", check=False).returncode:
        return
    published = records(tree_paths(root, "origin/main"))
    for key, ref, oid in claims(root):
        if key in published:
            git(root, "update-ref", "-d", ref, oid, check=False)


def occupied(root):
    result = set()
    refs = git(root, "for-each-ref", "--format=%(objectname)", "refs/heads/", "refs/remotes/origin/main").stdout.splitlines()
    for oid in set(refs):
        result.update(records(tree_paths(root, oid)))
    for path in worktrees(root):
        if not pathlib.Path(path).is_dir():
            raise RuntimeError("worktree unavailable; cannot safely number records: " + path)
        result.update(records(disk_paths(path)))
    result.update(key for key, _, _ in claims(root))
    return result


def next_number(root, kind, day, claim):
    prune_claims(root)
    used = occupied(root)
    number = max((n for k, d, n in used if k == kind and d == day), default=0) + 1
    if claim:
        head = git(root, "rev-parse", "HEAD").stdout.strip()
        while True:
            label = f"diary-{day}-{number:02d}" if kind == "diary" else f"{kind}-{number:04d}"
            p = git(root, "update-ref", "--create-reflog", "-m", "record claim from " + str(root),
                    "refs/claims/" + label, head, "0" * len(head), check=False)
            if p.returncode == 0:
                break
            # A concurrent claimant may win this number. Other failures must not spin forever.
            if git(root, "show-ref", "--verify", "--quiet", "refs/claims/" + label, check=False).returncode:
                raise RuntimeError(p.stderr.strip())
            number += 1
    return f"{number:02d}" if kind == "diary" else f"{number:04d}"
