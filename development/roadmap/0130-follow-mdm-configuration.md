---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0130 — Follow MDM configuration, and other tools' settings

Owner wish (2026-10-28 22:47): investigate following MDM (managed device) configuration and which settings it should cover, once every
setting proposed by the roadmap and the wishes exists. Investigate reading the managed settings of VS Code, Claude Code, Codex, Vibe and
Antigravity and matching them to ask's. This needed AemiHMMML (0109), which is done: TOML and YAML read, strict or recovering. Then possibly a package that parses other tools'
configuration, and an "AskMDM" built on it. Review the needs and the right architecture before building.

## Research done; the build waits on the owner (2026-11-22)

The owner, 2026-11-21: "among coding harnesses we should have the most customizable and tunable for mdm purpose". The research is
`development/research/mdm-configuration-2026-11.md`: how a managed Mac delivers forced preferences and how a command-line program reads
them (probed: CFPreferences reads a forced key of another domain and says it is forced; 3.8 ms for the first read of a process, so
it stays off the first frame's path); what Claude Code, Codex and VS Code offer (read); what ask's layers already give; a proposal in
eight parts (one managed layer from a profile and a root-owned file, every setting manageable as a requirement or a default, merge rules
per key, managed-only keys, fail closed, shown in `ask config`, MDM console manifests generated from the catalog, watched); and the
questions M1 to M8 for the owner. Nothing is built until they are answered.

