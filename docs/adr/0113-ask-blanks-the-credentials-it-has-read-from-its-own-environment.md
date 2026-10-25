---
status: accepted
date: 2026-10-25
---

# 0113 — ask blanks the credentials it has read from its own environment

## Context

ADR-0106 stopped a command inheriting ask's credential variables, and said so plainly: it did not stop a command *reading ask's own environment*.
Diary 20 then showed that it can. A sandboxed command recovered a stand-in key from its parent with `sysctl(KERN_PROCARGS2)`, while `ps` was refused,
so the key came back in the tool result and went to the provider. Roadmap 0072 stayed open for it.

## The probes (diary 2026-10-25-27)

| Claim | Probe | Verdict |
|---|---|---|
| A Seatbelt rule can deny the call | `sandbox-exec` with `process-info*` (target others), `process-info-pidinfo`, `sysctl-read` of `kern.procargs2` and of the `kern.proc` prefix, and the process-info kinds listed together | **REFUTED**: the key was read under each. Denying `sysctl-read` altogether broke Python before the call, so the sandbox governs sysctl but not this request. |
| ask's restricted-read profile already prevents it | A compiled C reader run under `--read workspace` | **REFUTED**: recovered. That profile allows only named sysctls and still leaked. |
| `unsetenv` removes the secret from what the kernel reports | A C parent that unsets, forks, and a child that reads the parent's procargs2 | **REFUTED**: still there. (A first version of this probe exec'd instead of forking, so the new image simply received the scrubbed environment; it proved nothing and was discarded.) |
| Overwriting the string in place does | Same, overwriting the value bytes of the `environ` entry | **CONFIRMED**: the entry reads back with the overwritten bytes. |

## Decision

1. ask takes **one snapshot of its environment at launch** (`LaunchEnvironment.values`, in `Sources/ask`), and everything in the executable reads that,
   never `ProcessInfo`. Library defaults that still read the live environment read only paths such as `XDG_*`, never a credential.
2. Once a run's `CommandEnvironment` is known (providers, presets, MCP references, configuration), ask **overwrites the values of every variable that policy
   withholds with NUL bytes, in place** (`ProcessEnvironment.conceal`, `AskCore`). The names stay. The pass-through list is ignored: ask has no use for a value
   after it has read it, and a command that is allowed a variable receives it from the snapshot.
3. The values reach what needs them by the snapshot: key resolution, MCP expansion, and the commands' own environment (`JobTable(environment:)`, now public).
4. `Reexec` (the `/reload` into a new build) starts the new process with `execve` and the snapshot. `execv` would hand the new process the blanked
   environment, and the next prompt would find no key; probe H fails that way (below).

## Evidence

- `Scripts/probe-bash-parent-environment.py`: exit 1 before, both modes (default sandbox and `--read workspace`); exit 0 after, the entry present and blank.
  Skipping the `conceal` call, and making `conceal` write zero bytes, each bring back exit 1.
- Probe H of `Scripts/probe-interactive.py` (`/reload` into a new build, then a prompt that needs the key) passes. With `execv` in place of `execve` it fails
  at "the next prompt works in the new process".
- `ProcessEnvironmentTests`: four tests, red against a stub first, for which entries change, that a predicate sees names only, and that the snapshot keeps what was blanked.
  These cover which entries change, not the kernel-visible copy; the probe covers that.

## Consequences

- A command can no longer recover a key from ask. The README's "known exposure" line is removed.
- A variable ask does not know is a secret (`MY_SERVICE_TOKEN`) is still inherited by commands and still readable from ask's process, unless configured as withheld.
  This protects the credentials ask itself uses, nothing more.
- ask's own memory still holds the keys it uses (in the provider it built). Reading another process's memory needs more than the same user and an ordinary
  command; that is not probed and not claimed either way.
- The blanking depends on `environ` still pointing at the strings the process started with. A `setenv` of the same name would make a heap copy and leave the
  original; ask calls `setenv` nowhere, and the probe shows the result, but a future caller would need to know.
- `Sources/ask` has no tests, so the wiring of the snapshot is guarded by probes and by `rg` for `ProcessInfo` in the executable's sources, not by a unit test.
