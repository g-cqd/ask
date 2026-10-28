---
status: accepted
date: 2026-10-19
---

# 0035 — The sandbox protects ask's own files and the secret stores by default

## Context

ADR-0020 chose capability policies that narrow inward, Seatbelt for child processes and in-process checks for
the file tools. This is the first of it that ships (roadmap 0017 and 0018), and the two halves are worth little
alone: a file tool that refuses `~/.config/ask` is no protection while `bash` can write it.

What needs protecting first is ask itself. The configuration directory holds the credentials, the trust store and
the provider keys, and a model that could write there could trust its own project file, change its own limits or
read the keys. The earlier fix, that `ask trust` needs a terminal, was named a speed bump at the time.

## Decision

**One policy, applied twice.** The read, write and edit tools ask `SandboxPolicy` before they touch a path, and
every `bash` command runs under `sandbox-exec` with the same policy compiled to a Seatbelt profile. A command
that was refused gets a note saying the sandbox may be why and what it protects, and the system prompt states
the policy, so the model neither retries nor hunts for a way round.

**The default protects:**
- **ask's configuration directory**: unreadable, unwritable and unmovable;
- **ask's state directory**: readable, unwritable (a cut command output is read back from there; the session
  is ask's record, not the model's to edit);
- **`~/.aws`, `~/.gnupg`, Keychains, `~/.netrc`, and ssh private keys**, unreadable. Not `~/.ssh/config` or
  `known_hosts`, which `git` over ssh needs. A key without an agent must be allowed by the user.

Both homes are covered, the account's and `$HOME`: `NSHomeDirectory()` ignores `$HOME` while a command's `~`
follows it, which the first probe of the feature found.

**The user adjusts it, the model cannot.** `--no-sandbox` turns it off for a run, by flag only, and ask says so.
A `sandbox` section in the user's `config.json` has `allowRead` (lifts a default secret store, such as
`~/.aws` for the aws CLI) and `denyRead` (adds directories). `allowRead` is read from the user's own file only,
because a project that could widen the sandbox would defeat it; `denyRead` only narrows, so a project may set
it. `allowRead` never lifts ask's own two directories, however spelled: a flag turns the sandbox off, a file
cannot. The config paths are in the protected set, so the agent cannot edit the file either.

## What a path rule does not stop, found by probing

Rules match paths, and `development/research/sandboxing-2026-10.md` records the attacks:
- **Renaming a protected directory's parent away, editing the copy, and renaming it back** worked: the config
  ended up tampered. So every ancestor of a protected path has unlink and rename denied, and a read-denied path
  is also unwritable, or moving `~/.aws` away would read it under another name.
- **A dangling symlink into a protected directory** creates the target when written through, **`..` after a name
  that does not exist** cannot be resolved the way the kernel would, and **case** differs on the default volume.
  Paths are therefore canonicalized before any decision: symlinks resolved, dangling ones followed,
  `..` after a missing name refused, comparison case-insensitive, and a path that cannot be resolved denied.
- Seatbelt applies its last matching rule, so the protections come after any allowance: a protected path inside
  a writable root stays protected.

## Cost (ADR-0016)

A sandboxed command costs about **8 ms more** to start: `bash echo` p50 1.9–2.3 ms → 9.7–11 ms, as the probe said. It
is `sandbox-exec`'s own startup: an empty profile costs the same as ours. ADR-0020's candidate, a launcher that
calls `sandbox_init_with_parameters` and then `exec`s, measured 11.3 ms against 10.8 and is rejected. The cost is
paid once per command, off the input path.

## Not done, and what remains true

- **The model can still write the executable** (it must, to build ask), so `/reload` stays a command only the
  user types, and an automatic reload still needs the user's confirmation (ADR-0034).
- **A path check and its use are two steps.** The tools use the canonical path they checked, which narrows the
  window, but a link swapped in between could still redirect a write until the file tools run in a sandboxed
  helper. `bash` is not exposed: Seatbelt checks at the operation.
  **Closed by ADR-0085** for `read`, `write` and `edit`: they no longer look the name up twice.
- **Network, write scope and read allow-lists** exist in the policy and the compiler and are tested, but nothing
  configures them yet: roadmap 0042.
- **Seatbelt does not nest** (ADR-0020): `ask --sandbox`, ask sandboxed as a whole, would make `sandbox-exec`
  fail, and is roadmap 0020.
- **`ask`'s own spawns are not sandboxed**: the self-check of a new build and the sign-in flows run as ask.
