#!/usr/bin/env python3
"""Self-test of Scripts/update-pins.py: pins move to the given heads and nothing else in a manifest changes; build trees are not read."""
import importlib.util
import pathlib
import tempfile

spec = importlib.util.spec_from_file_location("pins", pathlib.Path(__file__).with_name("update-pins.py"))
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)

OLD, NEW, OTHER = "a" * 40, "b" * 40, "c" * 40
manifest = f'''dependencies: [
    .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "{OLD}"),
    .package(
        url: "https://github.com/g-cqd/AemiRegex.git", revision: "{NEW}"),
    .package(url: "https://github.com/someone/else.git", revision: "{OLD}"),
    .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
]'''
heads = {"https://github.com/Aemi-Studio/aemi.git": NEW, "https://github.com/g-cqd/AemiRegex.git": NEW}
text, moved = pins.repinned(manifest, heads)
assert moved == [("https://github.com/Aemi-Studio/aemi.git", OLD, NEW)], moved
assert text == manifest.replace(f'aemi.git", revision: "{OLD}"', f'aemi.git", revision: "{NEW}"'), text
assert f'else.git", revision: "{OLD}"' in text, "a pin outside the family is left alone"
assert pins.repinned(text, heads)[1] == [], "current pins move nothing"
assert pins.repinned(manifest, {})[0] == manifest

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    for path in ["Package.swift", "Benchmarks/Package.swift", ".build/checkouts/x/Package.swift", ".swiftpm/Package.swift"]:
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_text(OTHER)
    found = [str(p.relative_to(root)) for p in pins.manifests(root)]
    assert found == ["Benchmarks/Package.swift", "Package.swift"], found

# What a pin commit stages: the manifests, and each Package.resolved beside one that the repository tracks (ask's Benchmarks
# has its own; AemiRegex tracks none).
import subprocess
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    for path in ["Package.swift", "Benchmarks/Package.swift", "Package.resolved", "Benchmarks/Package.resolved"]:
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_text(OTHER)
    subprocess.run(["git", "-C", str(root), "add", "Package.resolved", "Benchmarks/Package.resolved"], check=True)
    expected = ["Benchmarks/Package.swift", "Package.swift", "Benchmarks/Package.resolved", "Package.resolved"]
    assert pins.staged(root) == expected, pins.staged(root)
    subprocess.run(["git", "-C", str(root), "rm", "-q", "--cached", "Package.resolved"], check=True)
    assert pins.staged(root) == expected[:3], "an untracked lock is not staged"

names = [name for name, _ in pins.FAMILY]
assert names[0] == "aemi" and names[-1] == "ask", names

with tempfile.TemporaryDirectory() as directory:
    repo = pathlib.Path(directory)
    assert pins.gate_steps(repo) == [["swift", "build"], ["swift", "test"]]
    (repo / "Scripts").mkdir()
    (repo / "Scripts/analyzers.sh").write_text("")
    assert pins.gate_steps(repo)[-1] == ["Scripts/analyzers.sh"]
    (repo / ".ci").mkdir()
    (repo / ".ci/swift-ci").write_text("")
    assert pins.gate_steps(repo) == [[".ci/swift-ci", "local"]], "swift-ci's local run replaces the build, tests and analyzers"
    (repo / "Scripts/quality.sh").write_text("")
    assert pins.gate_steps(repo) == [["Scripts/quality.sh", "--check"]], "a quality script is the repository's own gate"
print("update-pins self-test: ok")
