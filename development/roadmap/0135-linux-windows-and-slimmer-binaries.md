---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0135 — Linux and Windows, Apple-only parts apart, universal binaries slimmed

Owner wish (2026-10-29 00:00): investigate Linux compatibility and move the Apple-only features into separate subpackages with
conditional builds, so a Linux build includes none of them. Include `lipo` slimming of the binaries. Investigate Windows as well.

## Still owed (investigation)

- Inventory what is Apple-only today: AskApple (Foundation Models), the Security framework when 0110 lands, IOKit-free power assertions
  (`ProcessInfo.beginActivity` exists on Linux but does nothing), `DistributedNotificationCenter` and `UserDefaults` in the appearance
  code, Network.framework, the sandbox itself (Seatbelt: Linux would need Landlock or seccomp), `pbcopy`-style helpers.
- TerminalKit and the Aemi packages already say which of them build on Linux; list what fails, per package, with a Linux container build.
- Windows: ConPTY instead of a PTY, no process groups, no Seatbelt. Likely a separate, later decision.
- `lipo`: ship a thin binary per architecture, or a universal one thinned on install; measure the size of each.
