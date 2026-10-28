---
status: accepted
date: 2026-10-26
---

# 0115 — The model is told the least about the sandbox

## Context

The sandbox exists to keep ask's own files and the person's secret stores out of the model's reach. It was also, at every turn, a description of itself.
Reading the source found six places where the model was handed the policy:

| Where | What the model read |
|---|---|
| The system prompt (`SandboxPolicy.summary`) | the absolute paths of the protected directories (`~/.config/ask`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, the state directory), the writable and readable roots, the network level, the SwiftPM flag |
| Every request after `narrow_sandbox` | the same summary again, appended as "Current session policy" |
| A refused `bash` command | `[This command ran in a sandbox, which may be why it was refused.` + the whole summary |
| A refused file tool | `Sandbox: <canonical path> is protected: <rule> cannot be read. Only the user can change this.` |
| A refused widening of a call's `sandbox` argument | `network any (this run allows localhost)`: the run's own policy |
| `narrow_sandbox`'s answer | the effective roots and network after intersecting with the run's policy |

None of it was needed to do the work. All of it was a map of what to look for, and a provider's log held it. A model that is told where the secrets are, even to be told it may
not touch them, has been told where the secrets are; the instruction to "not try to get around it" is the part of the prompt a hostile file can argue with.

## Decision

The model learns the sandbox only by a call being refused, and a refusal says only what was refused.

1. `SystemInstructions.text(workingDirectory:)` says where the model works and how to use jobs. It has no sandbox parameter and no sentence about one.
2. The loop's request is the stable system prompt and nothing else, so the prompt cache holds and a narrowing is not announced. `SandboxPolicy.summary` is deleted.
3. A refused file call is `Not permitted: <path>.` with the path **as the model gave it**: not the canonical path, not the rule, not who could change it (`ToolFailure.notPermitted`).
4. A refused `bash` command carries the operating system's own `Operation not permitted` and nothing of ours. The one note kept is for a program that starts a sandbox of its own,
   which Seatbelt cannot nest (SwiftPM): it names the program's own `--disable-sandbox` flag and nothing of this run's policy.
5. A refused widening, and a refused `reset`, answer `Not permitted: that request is refused.` The question put to the **person** still shows everything: the approval prompt is
   for the one who may widen, and it is theirs to read.
6. `narrow_sandbox` answers `Narrowed for the rest of the session.`

7. The skills block no longer says a skill "never changes the sandbox" (found by `probe-agent-run.py` M, on a machine with skills installed, after the unit tests passed): it says a skill never grants a permission.

The `sandbox` argument every tool takes, and `narrow_sandbox` itself, stay: they are a capability the model has (narrowing only), and their schema text says nothing about any run's policy.

## Consequences

- A model that never touches a protected path never learns one exists. One that does is told "not permitted" and the operating system's own error, which a command already prints.
- SwiftPM's manifest compile under the sandbox no longer has its flag in the prompt, so the first `swift build` may fail once and then say, in the tool result, what to do. That is the cost: one failed call
  for a model that uses SwiftPM, in exchange for no map of the sandbox in any other conversation.
- What remains, and is a decision for the person to flip: the model can still see that **a** sandbox exists, in the schema of the `sandbox` argument and in `narrow_sandbox`, because narrowing is a capability it has
  (ADR-0054, ADR-0057). Removing the argument and the tool would end the model's ability to narrow itself; this ADR does not.
- The person's own views are unchanged: `/config`, the status line and the approval prompt still describe the policy in full.

## Evidence

- The tests that asserted the leak were rewritten to assert its absence: `SystemInstructionsTests` (no sandbox word in the prompt however the run is restricted), `SessionNarrowingTests` (narrowing leaves the request's
  prompt as it was), `FileToolsSandboxTests` (`Not permitted: <path>.` exactly, no `Sandbox`, no `protected`), `BashSandboxTests` (a refused command's output has no policy word beyond the system's error and the
  path the command itself named), `NestedSandboxTests`, `ToolRegistrySandboxTests` and `NarrowSandboxToolTests` (the run's policy never in the answer).
- Three mutants, each put back and run: a file refusal that says `Sandbox: <path> is protected`, a prompt with `Sandbox: no network.` appended, and a nested-sandbox note that says "ask's sandbox". Each was killed
  (8 failures across `FileToolsSandboxTests`, `ReadSandboxTests`, `SystemInstructionsTests` and `NestedSandboxTests`).
- The tests that held the old behaviour had asserted it, so each rewritten test was red against the old code by construction: the old code produced the strings they now forbid.
- Four more tests asserted the old words (`CallSandboxTests`, `ReadSandboxTests`, `NarrowSandboxToolTests`, `FileToolsSandboxTests`' unresolvable path); they now assert `Not permitted: <path>.`
