#!/usr/bin/env python3
"""The target layering of ADR-0009, checked over the manifest (roadmap 0166).

    python3 Scripts/check-layers.py              reads `swift package dump-package`
    python3 Scripts/check-layers.py PACKAGE.json reads a dump already made (the self-test feeds it a broken one)

Each library target may depend only on the internal targets listed for it below, so the provider layer stays a leaf, the screen
knows nothing of the agent, and an upward edge is a red gate instead of a quiet import. A new library target fails until it is
placed here on purpose. Test targets may depend on any library, never on the executable; nothing depends on the executable.
Exit: 0 clean, 1 an edge the layering does not allow.
"""
import json
import subprocess
import sys

# ADR-0009's graph, with the targets added since (AskMCP, AskApple): each target's allowed internal dependencies.
ALLOWED = {
    "AskCore": set(),
    "AskAI": {"AskCore"},
    "AskMCP": {"AskAI", "AskCore"},
    "AskAgentCore": {"AskAI", "AskCore"},
    "AskApple": {"AskAI", "AskAgentCore", "AskCore"},
    "AskTools": {"AskAgentCore", "AskAI", "AskMCP", "AskCore"},
    "AskTUI": set(),
}


def internal_dependencies(target, names):
    for entry in target["dependencies"]:
        kind, value = next(iter(entry.items()))
        if kind in ("byName", "target") and value[0] in names:
            yield value[0]


def violations(package):
    targets = {target["name"]: target for target in package["targets"]}
    executables = {name for name, target in targets.items() if target["type"] == "executable"}
    found = []
    for name, target in sorted(targets.items()):
        dependencies = set(internal_dependencies(target, targets))
        for executable in sorted(dependencies & executables):
            found.append(f"{name} depends on the executable {executable}: nothing may")
        if target["type"] == "regular":
            if name not in ALLOWED:
                found.append(f"{name} is a new library target: place it in Scripts/check-layers.py's ALLOWED, per ADR-0009")
                continue
            for dependency in sorted(dependencies - ALLOWED[name]):
                found.append(f"{name} depends on {dependency}, which ADR-0009's layering does not allow")
    return found


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as file:
            package = json.load(file)
    else:
        dump = subprocess.run(["swift", "package", "dump-package"], check=True, capture_output=True, text=True)
        package = json.loads(dump.stdout)
    found = violations(package)
    for line in found:
        print(f"[FAIL] {line}")
    if not found:
        print("[OK] target layering (ADR-0009)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
