---
status: accepted
date: 2026-11-22
---

# 0168 — Managed configuration: requirements applied last, defaults first, from root-owned files

## Context

Roadmap 0130. The owner, 2026-11-21: ask's configuration should be "mdm compatible", the most tunable coding harness for MDM. The
research (`development/research/mdm-configuration-2026-11.md`) and the owner's answers of 2026-11-22: every key manageable, as a
**requirement** (no other layer changes it) or a **default** (a starting value the person may change); from a macOS profile's domain
`studio.aemi.ask`, a root-owned file, and later an HTTPS endpoint; a managed document that does not parse stops ask, named; console
schemas generated from the catalog; roadmap 0209 first. 0209 now declares every key once with the rule by which layers combine it
(`SettingMerge`: replaces, adds, narrows).

## Decision

1. **Two documents, each a `config.json`.** `requirements.json` and `defaults.json`, each with drop-ins (`requirements.d/*.json`,
   `defaults.d/*.json`, read in name order after the main file), in `/Library/Application Support/ask` on macOS and `/etc/ask` elsewhere.
   They use exactly the person's file format, every key included (the person's-own-file-only keys too), so an administrator writes
   what a person writes, and every error names its file and key. No new format, no `requirements` wrapper object.
2. **Order.** Managed defaults, then the person's file, the trusted project's, the environment and the flags, then the managed
   requirements. Applying requirements last is the lock, because each key combines by its declared rule: a replacing key takes the
   managed value; a protective list (`environment.withhold`, `sandbox.hide`) keeps the managed entries and may gain more below; a scope
   (`sandbox.write`, `read`, `network`) is intersected, so a flag cannot widen past it, while a lower layer may still narrow. A stricter
   value from below therefore still counts where the rule allows it, without a list of exceptions.
3. **Trusted only when root's.** A managed document, after symbolic links are resolved, must belong to root and be writable by no one
   else, as must the folder holding it; otherwise ask refuses to start and says which and why. A document that does not parse, or
   names an unknown key or a bad value, also stops ask, named (the owner's answer). Fail closed: a policy that cannot be read is not
   silently dropped.
4. **Shown.** A key a managed document set is attributed to `.managed(path)`, shown as the path with "(your organisation)".
5. **Phases.** This ADR's build is phase 1: the files, the order, the trust check, the source. Phase 2: run-time changes respect
   requirements (`/model`, `/config`, a resumed session), and managed-only keys (refusing `--no-sandbox` and `--yolo`, allowlists of
   providers, models and MCP servers). Phase 3: the macOS profile's domain, read from `/Library/Managed Preferences` only when such a
   file exists (the first CFPreferences call costs 3.8 ms, research §1). Phase 4: console schemas and a `.mobileconfig` generator from
   the catalog. Phase 5: an HTTPS endpoint.

## Consequences

- Until phase 2, a requirement holds at every load (start, reload after an edit) but `/model` can still change the model for one run.
- Tests cannot make root-owned files: the loader takes the managed folder and the owner it trusts, defaulting to the system's.
- `mcp` combines by server name, so a managed server replaces one of the same name below; an allowlist is phase 2's.

## Probes

Recorded in diary 2026-11-22-04: the order against each rule, the trust check against a file another user may write, and failing
closed.
