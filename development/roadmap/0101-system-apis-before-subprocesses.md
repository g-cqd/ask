---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0101 — System APIs before subprocesses

Owner wish (`ask-wishes.md`, 2026-10-28 17:06): use system APIs instead of subprocesses or system command-line tools whenever possible
(example: the clipboard API instead of `pbpaste`), written down as a guideline. The guideline is in `development/WHITE-PAPER.md`, Runtime
principles, "System APIs before subprocesses".

## Inventory (2026-10-28)

| Use | Where | Verdict |
| --- | --- | --- |
| `pbcopy` for copies | was `HostPasteboard` | replaced by `NSPasteboard` (ADR-0127, `8159b60`) |
| `caffeinate` | not yet built | build it on a power assertion (IOKit `IOPMAssertionCreateWithName` or `ProcessInfo.beginActivity`), roadmap 0090 |
| the shell for the model's commands | `JobProcess` | the point of the tool: stays |
| `sandbox-exec` | `JobProcess` | stays: `sandbox_init` is deprecated and has no public replacement; to recheck in `apple-docs` |
| `/bin/sh` watchdog | `JobWatchdog` | stays: it must outlive a SIGKILL of ask, which only another process can |
| MCP stdio servers | `StdioTransport` | the point: stays |
| `agy` binary | `AgyBinary` | the provider's own client: stays |
| ask `--self-check` | `SelfCheck` | checks a new build can start before a reload: stays |
| `git ls-files` | `ProjectLister` | git is the authority on what it ignores; reimplementing `.gitignore` rules is worse. Stays, with a reason in the code |

## Still owed

- A reason comment next to each remaining subprocess use that lacks one.
- Recheck `sandbox-exec` against the current Security and sandbox documentation.
- A source test that flags a new `Subprocess.run` or `Process()` outside the files above, so the inventory cannot drift.
