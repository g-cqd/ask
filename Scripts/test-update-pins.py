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

names = [name for name, _ in pins.FAMILY]
assert names[0] == "aemi" and names[-1] == "ask", names
print("update-pins self-test: ok")
