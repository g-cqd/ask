---
status: done
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
| `sandbox-exec` | `JobProcess` | stays: `sandbox_init` is deprecated and has no public replacement (rechecked 2026-10-29, below) |
| `/bin/sh` watchdog | `JobWatchdog` | stays: it must outlive a SIGKILL of ask, which only another process can |
| MCP stdio servers | `StdioTransport` | the point: stays |
| `agy` binary | `AgyBinary` | the provider's own client: stays |
| ask `--self-check` | `SelfCheck` | checks a new build can start before a reload: stays |
| `git ls-files` | `ProjectLister` | git is the authority on what it ignores; reimplementing `.gitignore` rules is worse. Stays, with a reason in the code |

## Still owed

- A reason comment next to each remaining subprocess use that lacks one.
- A source test that flags a new `Subprocess.run` or `Process()` outside the files above, so the inventory cannot drift.

## `sandbox-exec` rechecked through apple-docs (2026-10-29)

Asked through ask itself (Claude Haiku, the apple-docs MCP server only): 19 calls, 18 answered, one `browse` refused by the server ("Page
not found: security-entitlements"); 38.8 s, 478k input tokens (88% read from cache), 1.9k out.

- apple-docs has **no page for `sandbox_init`**: every result that contains the name only echoes the query. The authority is the SDK header,
  `usr/include/sandbox.h`: "This header is deprecated and may be removed in a future release", and `sandbox_init` is
  `API_DEPRECATED("No longer supported", macos(10.5, 10.8))`.
- The only documented way to confine a child is App Sandbox with `com.apple.security.inherit`
  (`xcode/embedding-a-helper-tool-in-a-sandboxed-app`, `bundleresources/entitlements/com.apple.security.app-sandbox`). It applies when the
  parent is itself in App Sandbox, which ask is not, and it cannot take a per-command profile. The model presented it as "the replacement";
  the pages it read do not say so.

So the row stands: `sandbox-exec` stays, with no public replacement.

## Closed (2026-10-31)

- `SubprocessInventoryTests` (AskCoreTests) fails when a file outside the inventory starts a process (`Subprocess.run`, `posix_spawn`,
  the `exec` family, `Process()`, `popen`, `system`, or an `import Subprocess`), and when an inventory entry starts nothing any more.
  Each entry carries its reason. Red when `ProjectLister.swift` was taken out of the list, green with it.
- The reason comments were already there: each file's own documentation says why it starts a process.
- `caffeinate` was never built: 0090 keeps the Mac awake with a power assertion.
