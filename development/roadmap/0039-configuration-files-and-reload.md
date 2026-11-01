---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0032
---

# 0039 — Configuration files, layers, trust and reload

The first step toward developing ask from inside ask: settings that live in files, and take effect without
a restart.

## What landed

- **`config.json`, JSON or JSON5,** in `~/.config/ask` and, once trusted, in a project's `.ask/`.
- **Layers:** defaults, user file, trusted project file, `ASK_*` environment, flags. `ask config` shows where each
  value came from.
- **Trust:** `ask trust` and `ask untrust`, bound to the file's SHA-256, and refused without a terminal.
- **Reload at each prompt,** all or nothing, announced with what changed.
- **AemiJSON findings** filed as issues 1 to 3, not worked around.

## Evidence

- **Format:** differential probe against `json5` 2.2.3 (ADR-0032).
- **Unit and probe:** 18 configuration tests; 14 compiling mutations caught, 3 of them by the real-binary
  probes (loop not rebuilt after a change, a broken file reported at every prompt, a flag dropped).
- **Probe H** (real binary): JSON5 and JSON, trust, a changed file, each layer over the one below, failures with
  line and column. **Probe F** (a running screen): edit, break and fix the file between prompts.
- **Live:** a JSON5 file, and a trusted project file, each chose the model for a real run.

## Left at the time, and where each went (2026-11-01)

- ~~**Slash commands** (`/config`, `/reload-config`)~~ Done: `/config` (0041, 0103); files are watched and re-read (0127).
- ~~**The sandbox must write-deny the config paths**~~ Done: the configuration directory is denied to commands
  (`SandboxPolicy+Standard`, `denyRead`, which also denies writing).
- **More keys** as features need them: thinking level, tool sets, hooks. Project files must not gain a key that
  can run code before the sandbox exists.
- ~~**Binary reload**~~ Done: `/reload` (0041). Keys keep being added as features need them.
