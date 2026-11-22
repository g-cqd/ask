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

## The owner's answers (2026-11-22)

- **Shape:** requirements and defaults, for every key, plus managed-only keys (Codex's split, Claude Code's coverage).
- **Sources:** the macOS profile's domain **`studio.aemi.ask`**, a root-owned file, and an HTTPS endpoint (later than the first two).
- **A managed document that does not parse:** ask refuses to start and names it.
- **For MDM consoles:** a Jamf JSON schema, a ProfileManifests manifest and a `.mobileconfig` generator, all from the catalog.
- **Order:** roadmap 0209 (one declaration per setting, with each key's merge rule) first, then this entry.
- Still open: M1 (the CFPreferences read measured inside ask), M3's user-level file (not chosen), M6 (other tools not read).

## Phase 1 built (2026-11-22, ADR-0168, diary 2026-11-22-04)

`requirements.json` and `defaults.json`, with drop-ins, in `/Library/Application Support/ask` (`/etc/ask` elsewhere): defaults first,
requirements last, each key by its declared rule; root's and writable by nobody else, or ask stops; shown in `ask config`. Next,
phase 2: `/model` and `/config` respect requirements; managed-only keys (refusing `--no-sandbox` and `--yolo`; allowlists of providers,
models and MCP servers). Then the profile's domain `studio.aemi.ask` (phase 3), console schemas and `.mobileconfig` (phase 4), an HTTPS
endpoint (phase 5).

