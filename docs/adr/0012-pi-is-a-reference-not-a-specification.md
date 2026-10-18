---
status: superseded
superseded-by: ADR-0014
amended-by: ADR-0013
date: 2026-10-18
---

# 0012 — pi is a reference, not a specification

> **Superseded by [ADR-0014](0014-our-own-bar-not-a-reference.md):** requirements are stated in ask's own
> terms, and research on other agents lives in `docs/research/`.
>
> **Amended by [ADR-0013](0013-damaged-sessions-load-by-default.md).** Damaged sessions now load by
> default with every repair reported, and pi findings are recorded in `docs/PI-FINDINGS.md`, never filed
> upstream. The principle below stands.

## Context

`ask` aims to be a better, lighter pi in Swift, and leans on pi's design: the session tree, compaction,
codemode, the provider gate. Copying a design also copies its defects unless someone checks. The user
asked that mistakes found in pi be fixed here and backed by tests, as a standing rule.

## Decision

1. **pi's behaviour is evidence about a good design, never authority.** When porting a behaviour, run
   pi's own code against edge cases before adopting it. pi 1.3.0 is installed locally, so this costs one
   script.
2. **A defect found in pi is fixed in ask, and a test pins the corrected behaviour.** The test carries a
   `Diverges from pi` doc comment naming the pi version and this ADR, so `rg "Diverges from pi"` lists
   every divergence and the reason for it.
3. **Intentional pi policy counts too.** Where pi chose a trade-off our principles reject, such as silent
   data loss, the divergence is recorded the same way, and described as a policy difference rather than
   as a bug. pi's authors may have reasons we do not see.
4. **Upstream reports are the user's call.** pi's CONTRIBUTING gates external contributions, and a public
   issue or PR acts on the user's behalf. Findings are offered, not filed unilaterally.

## Divergences found so far — probed, not read

Probe: `node Scripts/probe-pi-session-parsing.mjs` (set `PI_VERSION` for another release), which calls pi 1.3.0's exported `parseSessionEntries` and
`buildContextEntries` from
`~/.pi/agent/install/releases/1.3.0/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js`.

| Input | pi 1.3.0 | ask | Tests |
|---|---|---|---|
| final record cut off by a crash | record silently dropped | `tornFinalLine` | `SessionLogTests` torn-line pair |
| corrupt line mid-file | that record silently dropped | `malformedLine(n)` | `a corrupt record is reported with its line number` |
| blank line | skipped | `malformedLine(n)` | `a blank line is malformed rather than skipped` |
| unknown leaf id | silently selects the last entry | `unknownEntry` | restore and leaf-record tests |
| parent id absent | context silently truncated at the gap | `unknownEntry` | restore and orphan tests |

The cause in pi is visible in the source: `parseSessionEntries` calls `content.trim()` and catches every
`JSON.parse` failure with `// Skip malformed lines`, and `buildSessionPath` falls back with
`leaf ??= entries[entries.length - 1]`.

## Consequences

- ask refuses a damaged session where pi would load what it could. That is stricter and, for a user with
  a corrupt file, less forgiving. The answer is an **explicit** recovery path, not a silent one: a future
  `decode` option that keeps the readable prefix and reports exactly what it discarded. Recorded in
  roadmap 0008 as owed.
- Every future port from pi starts with a probe of pi's own code, the same way TerminalKit's emulator
  probes refuted our DECSTR assumption.
