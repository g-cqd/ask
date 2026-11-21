# Managed configuration (MDM): what others do, what ask has, what it could be — 2026-11-22

Roadmap 0130. The owner, 2026-11-21: "i'm really interested into making its configuration mdm compatible and among coding harnesses we
should have the most customizable and tunable for mdm purpose". 0130 asked for the needs and the architecture before anything is built.
Everything below marked **read** was read on 2026-11-22 at the address given; **probed** was run on this Mac; anything else is a question.

## 1. What a managed Mac gives a program (probed)

- **A configuration profile's `com.apple.ManagedClient.preferences` payload** forces preference keys of any domain (Apple's
  `devicemanagement/managedpreferences`, read). macOS writes them to `/Library/Managed Preferences/<domain>.plist` (device) and
  `/Library/Managed Preferences/<user>/<domain>.plist` (user), owned by root. This Mac is enrolled (Intune, `profiles status`) and holds
  13 such domains.
- **A command-line program reads them through CFPreferences, and can tell a forced key.** Probe (`/tmp/mdmprobe.swift`, 10 lines):
  `CFPreferencesCopyAppValue("GKFeatureGameCenterMultiplayerOtherPlayerTypesAllowed", "com.apple.gamed")` returned `0` and
  `CFPreferencesAppValueIsForced` `true`; a key the profile does not set returned nil and `false` (the probe can fail). No bundle, no
  entitlement, no subprocess (white paper: system APIs before subprocesses).
- **Its cost is not free.** The first CFPreferences read of a fresh process: **3.8 ms median** (p10 3.2, p90 4.9, 21 runs, a domain
  nobody manages) against 0.007 ms without it. That is a large share of the cold-start budget, so it cannot sit on the first frame's
  path. The two files' `stat` is the cheap gate: only a machine whose profile names ask's domain pays the read. Not yet measured inside
  ask itself, where the cost may overlap with what Foundation already does (open question M1).
- **Linux and Windows.** No equivalent API on Linux: everyone uses a root-owned file under `/etc` (below). Windows (registry policies)
  is out of scope while ask is macOS-first (roadmap 0135).

## 2. What other harnesses offer (read)

| | Claude Code | Codex | VS Code (Copilot) |
|---|---|---|---|
| Source | <https://code.claude.com/docs/en/managed-settings>, `/settings` | <https://learn.chatgpt.com/docs/enterprise/managed-configuration> | <https://code.visualstudio.com/docs/enterprise/policies> |
| macOS profile | domain `com.anthropic.claudecode`, the same keys as the file, nested as dictionaries | managed preferences carrying TOML as base64 (`config_toml_base64` read; the requirements key not read) | `.mobileconfig` sample shipped in the app; object values are JSON strings |
| File | `/Library/Application Support/ClaudeCode/managed-settings.json` + `managed-settings.d/*.json` (alphabetical drop-ins), `/etc/claude-code/` on Linux | `/etc/codex/requirements.toml`, system `config.toml`, legacy `managed_config.toml` | `/etc/vscode/policy.json` (Linux) |
| Server | claude.ai console, polled hourly; a "policy helper" executable | ChatGPT admin console ("Agent security"), self-hosted HTTPS endpoint | GitHub organisation policy |
| Kinds | managed = locked, except a few documented defaults (`model`, `autoCompactWindow`); locks such as `allowManagedPermissionRulesOnly` | **requirements** (constraints users cannot override) apart from **defaults** (starting values users change) | a fixed list of about 60 named policies, each locked |
| Several sources | `first-wins` by default, `merge` opt-in; lists union, locks take the strictest | requirements merged by precedence; a conflicting user value falls back to a compatible one, with a notice | machine over user |
| Invalid values | a document that does not parse refuses to start; a bad lock reads as its restrictive value ("fail closed"); per-field repair | a conflict falls back and notifies | the setting is not applied, logged |
| Stricter lower values | honoured for a listed set of keys (a user's `true` for a block wins over managed `false`) | "most restrictive decision wins" for command rules | — |
| What is shown | `/status` names the source in force and the sources skipped; `claude doctor` lists what was dropped | client notifications | "Policy Diagnostics" report: applied and non-applied policies |
| Coverage | every settings key, plus about 20 managed-only keys | security-sensitive keys and feature pins | only the settings Microsoft chose |

Gemini CLI, Cursor, opencode, pi and Amp: not read today (question M6).

**What the leaders share:** a root-owned layer above every other, a split between what is locked and what is a starting value, list
semantics that cannot be widened from below, allowlists for providers, models and MCP servers by identity, a way to see what is in force
and why, and a fail-closed reading of a damaged lock. **Where each falls short:** VS Code covers only the keys it chose; Codex needs
TOML in base64 inside a profile, which no MDM console can edit field by field; Claude Code's profile carries the keys but ships no
schema an MDM console can draw.

## 3. What ask has today (read in the source)

- **Layers:** defaults, `~/.config/ask/config.json`, the trusted project's `.ask/config.json`, environment, flags (docs/configuration.md,
  "Where a value comes from"); `providers.json` apart (ADR-0027); credentials in the keychain.
- **Semantics already fit for a lock:** protective lists add up (`sandbox.hide`, `environment.withhold`), scopes only narrow
  (`sandbox.write`, `sandbox.read`, `sandbox.network`), "your own file only" keys (20 rows of `SettingCatalog` say `user: true`), MCP
  masks that may only switch off (0127).
- **One catalog of every setting** (`SettingCatalog`, about 100 rows: path, kind, example, default, help) already generates
  `docs/config.example.jsonc` and the `/config` editor's rows. A per-key descriptor (roadmap 0209) would carry the merge rule too.
- **Watching:** one `KqueueWatcher` over the configuration files' directories (ADR-0131); an invalid edit keeps the last valid settings.
- **Not present:** a layer above the user's, a lock, a managed-only key, a schema for MDM consoles, a report of the source of each key
  outside `ui` and `skills` (`Configuration.keySources`).

## 4. A proposal: the most tunable harness for MDM (for the owner; nothing built)

1. **One managed layer, on top, from two places.** The profile's domain (proposed `com.g-cqd.ask`, M2) and a root-owned file
   (`/Library/Application Support/ask/managed.json` with `managed.d/*.json`, `/etc/ask/` on Linux). Read only when one exists (`stat`),
   then through CFPreferences on macOS; ignored unless owned by root and not writable by others (the threat is the person's own
   account editing its policy, M3).
2. **Every setting is manageable, not a chosen list.** The same keys as `config.json`, in two sections: `requirements` (locked: no
   user, project, environment or flag value changes it) and `defaults` (a starting value the person may change). Codex's split, with
   Claude Code's coverage.
3. **Each key's descriptor says how a lock combines** (needs 0209): a scalar replaces; a protective list adds; a scope intersects, so a
   flag such as `--write` or `--yolo` cannot widen past it; an allowlist (providers, models, MCP servers by command or URL, hosts for
   the network) is the managed one alone when locked; a lower value that is *stricter* still counts (Claude Code's exception list, here
   as a rule of the descriptor rather than a list).
4. **Managed-only keys** for what only an organisation sets: allowed providers and models, base URLs and gateways, refusing `--yolo`
   and `--no-sandbox`, MCP servers provided to everyone, hooks only from the managed layer, skills sources, session encryption
   required, retention of session files, a minimum ask version, and what may leave the machine (web fetch, telemetry if ever).
5. **Fail closed, and say so.** A managed document that does not parse: ask refuses to start and names it (Claude Code's choice;
   M4 is whether ask should instead run on the last good copy). A lock with a bad value reads as its restrictive value. Everything
   intact still applies (ADR-0013's rule).
6. **Shown, not hidden.** `ask config` and `/config` mark a locked key "set by your organisation" with its source (profile or file),
   refuse to edit it, and list keys a document set that ask does not know. A `/status`-like line names the managed source in force.
7. **Generated for MDM consoles**, which nobody does today: from the catalog, `ask config --mdm-manifest` writes a Jamf JSON schema and
   a ProfileManifests (iMazing Profile Editor, ProfileCreator) manifest, and `ask config --mdm-profile FILE` turns a `managed.json` into
   a signed-or-not `.mobileconfig`. Every setting then appears in the admin's console with its type, choices, default and help, and
   cannot drift (a test compares them, as for `config.example.jsonc`). The two formats are claims to check before building (M5).
8. **Watched like the other files**: `/Library/Managed Preferences` joins the kqueue watcher's directories, so a profile pushed while
   ask runs applies at the next idle moment.

## 5. Questions only the owner can settle

- **M1** Measure the CFPreferences read inside ask's cold start before choosing CFPreferences over reading the plist directly.
- **M2** The preference domain: `com.g-cqd.ask`, or the reverse-DNS domain still open for the editors' extensions (t278).
- **M3** Root-owned only, or also a user-level managed file for machines without MDM (Claude Code's HKCU-like fallback)?
- **M4** A broken managed document: refuse to start (Claude Code), or run on the last good copy with a warning?
- **M5** Which MDM console formats to generate first (Jamf JSON schema, ProfileManifests, both); signed profiles or not.
- **M6** Read Gemini CLI's, Cursor's and opencode's managed settings too before deciding (not read today).
- **M7** Server-delivered policy (an HTTPS endpoint, like Codex's self-hosted one) now, later, or never.
- **M8** Order: build on today's catalog now, or after 0209 (one declaration per setting) so each key's merge rule lives in one place.
