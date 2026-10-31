#!/usr/bin/env python3
"""Moves the family's revision pins to each repository's head, in dependency order (roadmap 0166).

    python3 Scripts/update-pins.py            the plan: which pins would move, from what to what (nothing is changed)
    python3 Scripts/update-pins.py --apply    do it: each repository in order, its gate between, one signed commit and push each
    python3 Scripts/update-pins.py --root DIR the directory holding the clones (default: the one holding ask)

Dependabot and Renovate read version requirements, not `revision:` pins, and cannot run one repository's gate before the next moves.
This does what was done by hand (ask 74a1963, 35c8461): for each repository after aemi, on a clean, current `main`, every manifest's
family pins are set to the upstreams' heads on GitHub, `swift package resolve` writes Package.resolved, the repository's gate runs,
and the change is committed (signed) and pushed, because the next repository resolves its pins from GitHub. A failed gate stops the
run and leaves that repository's tree as it is, to read. Pins that are already current change nothing.
Exit: 0 done or nothing to do, 1 a gate or a git step failed, 2 a clone is missing or not clean.
"""
import argparse
import pathlib
import re
import subprocess
import sys

# Dependency order: each repository pins only ones before it.
FAMILY = [
    ("aemi", "https://github.com/Aemi-Studio/aemi.git"),
    ("AemiRegex", "https://github.com/g-cqd/AemiRegex.git"),
    ("AemiMarkdown", "https://github.com/g-cqd/AemiMarkdown.git"),
    ("AemiJSON", "https://github.com/g-cqd/AemiJSON.git"),
    ("TerminalKit", "https://github.com/g-cqd/TerminalKit.git"),
    ("ask", "https://github.com/g-cqd/ask.git"),
]
PIN = re.compile(r'(url:\s*"(?P<url>[^"]+)"\s*,\s*revision:\s*")(?P<sha>[0-9a-f]{40})(")')


def git(repo, *args, check=True):
    return subprocess.run(["git", "-C", str(repo), *args], check=check, capture_output=True, text=True).stdout.strip()


def manifests(repo):
    """Every Package.swift of the repository: the package's own and its benchmark and plugin packages, which pin the same stack."""
    return sorted(
        path for path in repo.rglob("Package.swift")
        if not any(part in (".build", ".swiftpm", "checkouts") for part in path.relative_to(repo).parts))


def repinned(text, heads):
    """`text` with each family pin set to its head, and the pins that moved as (url, old, new)."""
    moved = []

    def replace(match):
        new = heads.get(match["url"])
        if new is None or new == match["sha"]:
            return match[0]
        moved.append((match["url"], match["sha"], new))
        return match[1] + new + match[4]

    return PIN.sub(replace, text), moved


def gate(repo):
    """The repository's own gate: its quality script when it has one, else a build and the tests; its analyzers either way."""
    steps = []
    if (repo / "Scripts/quality.sh").exists():
        steps.append(["Scripts/quality.sh", "--check"])
    else:
        steps += [["swift", "build"], ["swift", "test"]]
        if (repo / "Scripts/analyzers.sh").exists():
            steps.append(["Scripts/analyzers.sh"])
    for step in steps:
        print(f"    $ {' '.join(step)}", flush=True)
        if subprocess.run(step, cwd=repo).returncode != 0:
            return False
    return True


def plan(root, heads):
    """For each repository after the first: its manifests' pins that would move."""
    result = []
    for name, _ in FAMILY[1:]:
        repo = root / name
        changes = []
        for path in manifests(repo):
            _, moved = repinned(path.read_text(), heads)
            changes += [(path.relative_to(repo), *change) for change in moved]
        result.append((name, changes))
    return result


def head(repo):
    git(repo, "fetch", "-q", "origin")
    return git(repo, "rev-parse", "origin/main")


def apply(root):
    for name, url in FAMILY:
        repo = root / name
        if git(repo, "status", "--porcelain", "--untracked-files=no"):
            print(f"[FAIL] {name} has uncommitted changes")
            return 2
        if git(repo, "rev-parse", "--abbrev-ref", "HEAD") != "main":
            print(f"[FAIL] {name} is not on main")
            return 2
        git(repo, "pull", "-q", "--ff-only", "origin", "main")
        heads = {other_url: head(root / other) for other, other_url in FAMILY[: [n for n, _ in FAMILY].index(name)]}
        moved = []
        for path in manifests(repo):
            text, changes = repinned(path.read_text(), heads)
            if changes:
                path.write_text(text)
                moved += changes
        if not moved:
            print(f"[OK] {name}: pins current")
            continue
        summary = ", ".join(sorted({f"{u.rsplit('/', 1)[1].removesuffix('.git')} {new[:7]}" for u, _, new in moved}))
        print(f"== {name}: {summary}", flush=True)
        if subprocess.run(["swift", "package", "resolve"], cwd=repo).returncode != 0 or not gate(repo):
            print(f"[FAIL] {name}: the gate failed with the new pins; the tree is left as it is")
            return 1
        git(repo, "add", "-A", "--", *[str(p.relative_to(repo)) for p in manifests(repo)], "Package.resolved")
        git(repo, "commit", "-S", "-q", "-m", f"build: pins {summary} (Scripts/update-pins.py in ask)")
        git(repo, "push", "-q", "origin", "main")
        print(f"[OK] {name}: {git(repo, 'rev-parse', '--short', 'HEAD')} pushed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    options = parser.parse_args()
    missing = [name for name, _ in FAMILY if not (options.root / name / ".git").exists()]
    if missing:
        print(f"[FAIL] no clone of {', '.join(missing)} in {options.root}")
        return 2
    if options.apply:
        return apply(options.root)
    heads = {url: head(options.root / name) for name, url in FAMILY}
    # A dry run sees only what moves to today's heads; a cascade moves later pins again, to the commits it makes.
    for name, changes in plan(options.root, heads):
        if not changes:
            print(f"[OK] {name}: pins current")
        for path, url, old, new in changes:
            print(f"{name} {path}: {url.rsplit('/', 1)[1].removesuffix('.git')} {old[:7]} → {new[:7]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
