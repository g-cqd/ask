---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0119 — The pinned aemi revision is gone upstream

Found while building the benchmarks (roadmap 0114). ask, TerminalKit and AemiJSON all pin `Aemi-Studio/aemi` at
`785c6b25cb3f4dc16ca2334fd69428fae4ee0b01`. That commit is no longer on GitHub: `git ls-remote` lists `main` at `f6da05c`, and the
pinned commit is not its ancestor, which points to a history rewrite. SwiftPM refused to resolve it for the Benchmarks package
("could not find the commit"); ask still builds here only because the commit is in the local `.build/repositories` cache. The benchmarks
were built by fetching the commit from that cache, locally.

## Still owed

- Confirm from a fresh clone in a temporary directory that ask fails to resolve, so the size of the problem is known, not assumed.
- Find the commit on the new history that matches `785c6b2` (same tree, or the same change), and move the pin in aemi's dependents
  together: TerminalKit, AemiJSON, aemiregex if it pins aemi, then ask. SwiftPM needs one revision per package in the graph.
- Check the other Aemi-family pins against their remotes the same way.
