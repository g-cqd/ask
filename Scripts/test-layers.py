#!/usr/bin/env python3
"""Self-test of Scripts/check-layers.py: a manifest with each kind of forbidden edge is refused, a clean one is not."""
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location("layers", pathlib.Path(__file__).with_name("check-layers.py"))
layers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layers)


def target(name, kind="regular", *dependencies):
    return {"name": name, "type": kind, "dependencies": [{"byName": [d, None]} for d in dependencies]}


clean = {"targets": [
    target("AskCore"), target("AskAI", "regular", "AskCore"), target("AskAgentCore", "regular", "AskAI"),
    target("AskTUI"), target("ask", "executable", "AskAgentCore", "AskTUI"), target("AskAITests", "test", "AskAI"),
]}
assert layers.violations(clean) == [], layers.violations(clean)

broken = {"targets": clean["targets"] + [
    target("AskMCP", "regular", "AskAgentCore"), target("AskNew"), target("AskTUITests", "test", "ask"),
]}
found = layers.violations(broken)
assert any("AskMCP depends on AskAgentCore" in line for line in found), found
assert any("AskNew is a new library target" in line for line in found), found
assert any("AskTUITests depends on the executable ask" in line for line in found), found
assert len(found) == 3, found
print("check-layers self-test: ok")
