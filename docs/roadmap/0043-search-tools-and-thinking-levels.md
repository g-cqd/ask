---
status: not-started
blocked-by:
date: 2026-10-19
---

# 0043 — Search tools, and a thinking level

The two gaps left between ask's tool set and what a daily coding session leans on.

## Search tools

The model searches with `bash` and `rg` today. That works, and costs a spawn (about 2 ms, about 10 ms sandboxed) and
whatever `rg` prints, uncapped by shape: a search that matches a lot arrives as a wall of lines.

- **`grep`** (a regex over files, with a glob, a context size and a match limit), **`find`** (paths by glob) and
  **`ls`** (a directory, sorted, with sizes), each capped by count before it is capped by bytes, and each checked
  against the sandbox policy for the paths it reads.
- **Measure before building:** the same search through `bash rg` and through the tool, on this repository, for time and
  for tokens returned. A tool that moves neither is not worth its place in every request's tool list: each definition
  is sent with every request (and cached), so it has a cost of its own.

## A thinking level

Providers differ: Anthropic's extended thinking with a budget, OpenAI's reasoning effort. One setting, `off`, `low`,
`medium`, `high`, mapped per provider, in `config.json` and as a flag, shown on the status line.

## Done when

A probe shows each search tool returning what `rg` and `find` return on the same tree, capped, and refused on a
protected path; and the thinking level changes the request the provider receives, per provider, on a fake server.
