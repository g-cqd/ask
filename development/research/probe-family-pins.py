#!/usr/bin/env python3
"""Reads the dependency pins of every package under a directory and answers the three questions a repin needs.

  drift   which revision of each package every manifest pins, and how far each is behind that package's origin/main
  check   whether each manifest's whole transitive graph, at the revisions it pins, names every package once
          (SwiftPM refuses a package required at two revisions: analyzerkit ADR-0025)
  order   the order repos must be repinned in, and what one bump forces

Example: development/research/probe-family-pins.py --root ~/Developer/g-cqd all
Read-only: it runs `git fetch` nowhere; it reads each manifest from the working tree, and pinned manifests with `git show`.
Only `.package(url: "https://github.com/<owner>/<repo>", revision: "<40 hex>")` edges are read; other spellings are reported.
"""
import argparse
import collections
import os
import re
import subprocess
import sys
import time

EDGE = re.compile(
    r'\.package\(\s*url:\s*"https://github\.com/(?:g-cqd|Aemi-Studio)/([^/"]+?)(?:\.git)?"\s*,\s*([^)]*?)\)', re.S)
REVISION = re.compile(r'revision:\s*"([0-9a-f]{40})"')


def git(root: str, repo: str, *args: str) -> str | None:
    done = subprocess.run(["git", "-C", os.path.join(root, repo), *args], capture_output=True, text=True, check=False)
    return done.stdout if done.returncode == 0 else None


class Family:
    def __init__(self, root: str) -> None:
        self.root = root
        self.repos = {
            name.lower(): name
            for name in sorted(os.listdir(root))
            if os.path.isfile(os.path.join(root, name, "Package.swift")) and os.path.exists(os.path.join(root, name, ".git"))
        }
        self.cache: dict[tuple[str, str | None], list[tuple[str, str | None, str]] | None] = {}

    def edges(self, repo: str, revision: str | None = None) -> list[tuple[str, str | None, str]] | None:
        """(dependency, pinned revision or None, spelling) for the manifest at `revision` (None: the working tree)."""
        key = (repo, revision)
        if key not in self.cache:
            if revision:
                text = git(self.root, repo, "show", f"{revision}:Package.swift")
            else:
                with open(os.path.join(self.root, repo, "Package.swift"), encoding="utf-8") as handle:
                    text = handle.read()
            found = None
            if text is not None:
                found = []
                for match in EDGE.finditer(text):
                    pinned = REVISION.search(match.group(2))
                    found.append((self.repos.get(match.group(1).lower(), match.group(1)),
                                  pinned.group(1) if pinned else None, " ".join(match.group(2).split())[:40]))
            self.cache[key] = found
        return self.cache[key]

    def closure(self, repo: str) -> tuple[dict[str, set[str]], dict[str, dict[str, set[str]]]]:
        seen: dict[str, set[str]] = {}
        who: dict[str, dict[str, set[str]]] = collections.defaultdict(lambda: collections.defaultdict(set))
        stack: list[tuple[str, str | None]] = [(repo, None)]
        visited: set[tuple[str, str | None]] = set()
        while stack:
            name, revision = stack.pop()
            if (name, revision) in visited:
                continue
            visited.add((name, revision))
            for dependency, pinned, _ in self.edges(name, revision) or []:
                if pinned:
                    seen.setdefault(dependency, set()).add(pinned)
                    who[dependency][pinned].add(name if revision is None else f"{name}@{revision[:7]}")
                    stack.append((dependency, pinned))
        return seen, who


def drift(family: Family) -> None:
    by: dict[str, dict[str, list[str]]] = collections.defaultdict(lambda: collections.defaultdict(list))
    unpinned = 0
    for repo in family.repos.values():
        for dependency, pinned, spelling in family.edges(repo) or []:
            if pinned:
                by[dependency][pinned].append(repo)
            else:
                unpinned += 1
                print(f"  not a revision pin: {repo} -> {dependency} ({spelling})")
    print(f"{'package':16s} {'pinned by':>9s} {'revisions':>9s}  (revision, repos, commits behind origin/main)")
    for dependency, revisions in sorted(by.items(), key=lambda item: -sum(len(v) for v in item[1].values())):
        local = family.repos.get(dependency.lower())
        head = (git(family.root, local, "rev-parse", "origin/main") or "").strip() if local else ""
        parts = []
        for revision, repos in sorted(revisions.items()):
            behind = (git(family.root, local, "rev-list", "--count", f"{revision}..origin/main") or "?").strip() if local else "?"
            parts.append(f"{revision[:7]} x{len(repos)} ({'HEAD' if revision == head else behind + ' behind'})")
        print(f"{dependency:16s} {sum(len(v) for v in revisions.values()):9d} {len(revisions):9d}  {'; '.join(parts)}")
    print(f"\n{sum(1 for r in family.repos.values() if family.edges(r))} manifests with pins; {unpinned} edges not pinned by revision")


def check(family: Family) -> int:
    started = time.time()
    bad = 0
    checked = 0
    for repo in family.repos.values():
        if not family.edges(repo):
            continue
        checked += 1
        seen, who = family.closure(repo)
        for dependency, revisions in seen.items():
            if len(revisions) > 1:
                bad += 1
                print(f"CONFLICT in {repo}: {dependency} is pinned as " + ", ".join(
                    f"{r[:7]} by {sorted(who[dependency][r])[:3]}" for r in sorted(revisions)))
    print(f"{checked} manifests checked, {bad} conflicts, {len(family.cache)} manifests read, {time.time() - started:.1f} s")
    return 1 if bad else 0


def order(family: Family) -> None:
    deps = {
        repo: {d for d, p, _ in family.edges(repo) or [] if p and d.lower() in family.repos and d != repo}
        for repo in family.repos.values()
    }
    level: dict[str, int] = {}

    def depth(repo: str, trail: tuple[str, ...] = ()) -> int:
        if repo in level:
            return level[repo]
        if repo in trail:
            return 0
        level[repo] = 0 if not deps.get(repo) else 1 + max(depth(d, (*trail, repo)) for d in deps[repo])
        return level[repo]

    for repo in deps:
        depth(repo)
    print("repin order (a repo waits for everything above it to have a pushed commit):")
    for number in sorted(set(level.values())):
        print(f"  level {number}: {', '.join(sorted(r for r, n in level.items() if n == number))}")
    users: dict[str, set[str]] = collections.defaultdict(set)
    for repo, ds in deps.items():
        for d in ds:
            users[d].add(repo)

    def downstream(repo: str, acc: set[str] | None = None) -> set[str]:
        acc = set() if acc is None else acc
        for user in users.get(repo, ()):
            if user not in acc:
                acc.add(user)
                downstream(user, acc)
        return acc

    print("\nwhat one bump forces (repos needing a new pin commit):")
    for repo in sorted(users, key=lambda r: -len(downstream(r))):
        print(f"  {repo:16s} {len(downstream(repo)):3d} repos")
    print(f"\nlongest chain: {max(level.values()) + 1} repos")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["drift", "check", "order", "all"])
    parser.add_argument("--root", default=os.getcwd(), help="directory holding the repositories (default: here)")
    arguments = parser.parse_args()
    family = Family(os.path.expanduser(arguments.root))
    status = 0
    if arguments.command in ("drift", "all"):
        drift(family)
        print()
    if arguments.command in ("check", "all"):
        status = check(family)
        print()
    if arguments.command in ("order", "all"):
        order(family)
    sys.exit(status)


if __name__ == "__main__":
    main()
