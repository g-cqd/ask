---
status: accepted
date: 2026-11-22
---

# 0166 — The settings' value types live once, in AskCore, and AskTUI may import it

## Context

Roadmap 0209 (research `rationalisation-2026-11.md` §2.1): adding `ui.dim` touched about eleven places in four targets. Seven
`*Preference` enumerations in AskAgentCore have a twin in AskTUI (`ScreenDim`, `SpinnerStyle`, `TimeoutDisplay`,
`QueuedAfterInterrupt`, `ScreenAppearance`, …), bridged by `rawValue` in `AskSession/RunSettings+Screen.swift` with a silent fallback:
a twin whose cases drift from its pair falls back to the default and no test says so. The twins exist because ADR-0009's layering gives
AskTUI no internal dependency (`Scripts/check-layers.py`: `"AskTUI": set()`).

The owner answered on 2026-11-08 (§5.1): **AskTUI may depend on one leaf target that holds the shared value types.** On 2026-11-22 the
owner set the order: 0209 first, then the MDM work (roadmap 0130), which needs each setting's merge rule declared once.

## Decision

1. **The leaf target is AskCore, not a new one.** AskCore already has no internal dependency (budgets, launch directory, process
   environment; about 160 lines), and ADR-0009's graph already lets AskAgentCore, AskAI and AskMCP import it (checked 2026-11-22:
   none does yet; the executable and AskSession do). Its one external dependency, AemiJSON, is one
   AskTUI already links. A new target would add a module and a layering rule for no difference in what the binary links: the shipped
   `ask` links every target either way, so the link weight does not change (white paper: the discipline is on what is linked).
2. **AskTUI may import AskCore, and only AskCore** of ask's targets: `check-layers.py` gets `"AskTUI": {"AskCore"}`; the dependency
   audit declares it.
3. **What moves into AskCore**: the value types a setting and the screen share — the enumerations of choices (`dim`, `spinner`,
   `appearance`, `timeout`, `notify`, `statusPath`, `statusPathSide`, `sessionTint`, `interruptKeys`, `queuedOnStop`, `paths`), each
   declared once under the screen's name or the setting's, whichever reads better at both uses. The configuration's parsing,
   layering and catalog stay in AskAgentCore; the screen's drawing stays in AskTUI.
4. **Then each setting gets one descriptor** (0209 step 2): its path, type, default, help, catalog row and **merge rule** (replace,
   add a protective list, narrow a scope, managed-only), as a value in a table, with no macros and no build-time generation.

## Consequences

- The `rawValue` bridge and `RunSettings.word` go; the mapping becomes plain assignments, and a drifted twin cannot exist.
- AskTUI can no longer be built without AskCore. AskCore must stay a leaf with no dependency on the screen, which the layering check
  enforces.
- The MDM layer (0130) reads each key's merge rule from its descriptor instead of a list kept beside the parser.
- Not decided here: whether `SettingCatalog` itself moves to AskCore (it reads AskAI's model types today).
