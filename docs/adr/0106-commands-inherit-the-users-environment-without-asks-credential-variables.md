---
status: accepted
date: 2026-10-25
---

# 0106 — Commands inherit the user's environment without ask's credential variables

## Context

Roadmap 0072 reproduced credentials entering tool results through bash's inherited environment. File protections do not remove environment entries.
A minimal environment also removes workflow settings; inheriting everything exposes credentials ask already knows it consumes.
This decision covers inheritance, not isolation of ask's process memory or its original environment from OS inspection.

## Decision

1. At the composition root, collect credential names from Anthropic's actual authentication readers, all provider presets, variable references in
   `providers.json` keys, and `${NAME}` references in configured MCP environment values and headers. Withhold these and `ANTHROPIC_*` / `ASK_*`.
   Names come from the readers' own definitions, not a second provider table. Inactive providers and servers still count.
2. Snapshot the parent environment once in `JobTable`; every launch filters that snapshot using its `ToolContext` policy. Supply the resulting custom
   environment to both ordinary and sandboxed jobs. Foreground and background commands use the same path.
3. `environment.pass` names exact variables allowed through the built-in withholding; `environment.withhold` adds exact names or trailing-star prefixes.
   Explicit withholding wins over passing, across additive configuration layers. A project may withhold more but may not pass any variable.
4. Variable names contain ASCII letters, digits and underscores, cannot begin with a digit, and have at most 128 bytes before a prefix's star.
   Each list holds at most 256 distinct entries. Configuration descriptions report names and policy, never values.
5. Library callers retain `.inherit` unless they explicitly provide a policy. The executable always supplies its credential policy.
6. Do not call this a complete secret boundary. Unknown secret variables remain inherited unless explicitly withheld. A command may still access
   credentials through independent OS/process channels; those require separate sandbox work.

## Evidence

Diary 2026-10-25-20 records the red/green end-to-end probe, selected tests, mutation results, and the process-inspection counterexample.
`Scripts/probe-bash-environment.py` distinguishes default withholding, explicit passing, additional withholding, and retained `HOME`.
A controlled clean-HOME comparison lost git's `GIT_CONFIG_GLOBAL` marker and gh's `GH_CONFIG_DIR` editor under a minimal environment; Swift's version command worked in both.
Selective withholding preserves those workflow settings. This does not establish that an allow-list would make every development command fail.

> **Update:** the residual exposure below was closed by [ADR-0113](0113-ask-blanks-the-credentials-it-has-read-from-its-own-environment.md). This record is otherwise unchanged.

## Consequences

Normal development variables survive. A user can deliberately pass a provider key to a command, but a repository cannot request that permission.
MCP discovery and expansion use one reference walk, so a header's interpolation syntax does not drift from credential-name discovery.

**Residual exposure:** on the tested macOS host a sandboxed command can use `sysctl(KERN_PROCARGS2)` to recover a stand-in key from ask's parent
process environment. Blocking `ps` did not block that call. Inheritance scrubbing is worthwhile but roadmap 0072's stronger no-tool-result claim
remains unmet. No claim is made that this stops malicious commands from obtaining credentials through every available channel.
