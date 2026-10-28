# Sandboxing on macOS: probes and other agents (2026-10-18/19)

Evidence behind ADR-0020. Probes ran on macOS 27.2 (26B5112a); `probe-seatbelt.sh` reproduces them.

## Seatbelt (`sandbox-exec`, `sandbox_init`)

| Claim | Probe | Result |
|---|---|---|
| `sandbox-exec` ships | `ls -l /usr/bin/sandbox-exec`, man page | Present (built Oct 10), marked **DEPRECATED** in favour of App Sandbox |
| In-process API exists | exports of `libsystem_sandbox.dylib` | `sandbox_init`, `sandbox_init_with_parameters`, `sandbox_init_from_pid` |
| Network can be denied | `(deny network*)`, curl | Denied; even DNS fails ("Could not resolve host") |
| Localhost-only works | `(allow network* (remote ip "localhost:*"))` | localhost 200, example.com denied. Seatbelt sees IPs and ports, **not domains** |
| Writes confined to a path | `(deny file-write*)(allow file-write* (subpath …))` | Inside ok, outside EPERM |
| Reads denied by path | `(deny file-read* (subpath …))` | EPERM on the secret, other reads ok |
| Children inherit | bash → cat under a read denial | Still denied |
| **Profiles nest** | sandbox-exec inside sandbox-exec; and `sandbox_init` then a child `sandbox-exec` | **No.** `sandbox_apply: Operation not permitted` (exit 71) in both. A sandboxed process cannot narrow further with Seatbelt |
| Parameters are injection-safe | `-D WORK='/tmp") (allow file-write* …'` | Treated as data; the write stays denied |
| Paths must be canonical | profile `/tmp/…` against real `/private/tmp/…` | Denied: rules match resolved paths only, failing **closed** |
| In-process enforcement | `sandbox_init` then `fopen` for write | Denied after init |
| Cost per spawn | 200 runs, `bash -c true` with and without `sandbox-exec` | p50 2.56 ms → **9.55 ms** (+7 ms), p95 3.01 → 10.63 ms |
| Denials are observable | unified log, `--info --debug`, `(with report)`, `(debug deny)` | The kernel logs `Sandbox: proc(pid) deny(1) op path` for some processes, but **not for these probes**. Open question |

## Other agents, read from their installed binaries

- **Codex 0.163.0** (`strings` of the binary):
  - modes `read-only`, `workspace-write` and `danger-full-access`;
  - a `(deny default)` base policy that allows what a process needs (`/dev/null`, `/dev/tty`, `/dev/ptmx`, `/etc`, system and Homebrew libraries) plus parameterised roots;
  - runs `/usr/bin/sandbox-exec` around each command, while Codex itself stays unsandboxed;
  - allows localhost network, for a proxy, and named unix sockets;
  - exports `CODEX_SANDBOX` and `CODEX_SANDBOX_NETWORK_DISABLED` to children.
- **Claude Code** (strings of its binary):
  - sandboxes each command;
  - network goes through a local HTTP/SOCKS proxy with `allowedDomains`;
  - filesystem `allowRead` / `denyRead`, `excludedCommands` and `allowLocalBinding`;
  - the model may ask per command for `dangerouslyDisableSandbox` or extra `allowed_domains`, both behind a permission gate; the prompt says changing policy is the user's decision, not the model's;
  - denials reach the model in a `<sandbox_violations>` block.

## Heavier isolation

- **Apple `container` 1.5.0** is installed (Homebrew). It runs Linux in lightweight VMs; its API server was not running. That is a whole-session isolation option for later, not a per-call one.
- **App Sandbox** needs entitlements and signing, and applies to an app, not to arbitrary child commands. It does not fit an agent's children.

## Protecting ask's own files (2026-10-19, macOS 27.2): what a path rule does not stop on its own

Reproduce with `probe-sandbox-protect.sh`, `probe-sandbox-ancestor.sh` and `probe-sandbox-cost.py`. The profile is
allow-default with denials over a fake home holding `~/.config/ask`, `~/.ssh`, `~/.aws` and a workspace.

| Claim | Probe | Result |
|---|---|---|
| Direct write, overwrite, rename in, unlink, hard link, chmod, touch of a protected file | `sandbox-exec` with `(deny file-write* (subpath ASK))` | All refused (`Operation not permitted`) |
| A wrong-case spelling (`.CONFIG/ASK`) | the same on the case-insensitive volume | Refused: Seatbelt canonicalizes case |
| A symlink made elsewhere, then written through | `ln -s protected work/link && echo x > work/link` | Refused: the rule matches the resolved path |
| Read of credentials, a private key; `ls` of the directory | `(deny file-read* …)` | Refused. `~/.ssh/config` stays readable, which `git` over ssh needs |
| **Renaming a protected directory's parent away, editing the copy, renaming it back** | `mv ~/.config ~/.config-away && echo x > ~/.config-away/ask/config.json && mv ~/.config-away ~/.config` | **Succeeded: the config ended up `TAMPERED`.** Rules match paths, and the moved directory has another path |
| The same with `(deny file-write-unlink (literal PARENT))` | the same attack | Refused at the first `mv`; the config survives |
| Moving a *read-denied* directory away to read it under another name | `mv ~/.aws ~/x; cat ~/x/credentials` | Would succeed unless the directory is also unwritable and its parent guarded; hence "unreadable implies unwritable" |
| `git init` and commit, and `swift build -c release` in the workspace | under the profile | Both work: allow-default plus denials does not disturb builds |
| `realpath(3)` and case | wrong-case aliases of existing paths | Returns the on-disk case. It fails (`ENOENT`) for a path that does not exist yet, so a new file's canonical form is its deepest existing directory plus the rest |
| Network `none` / `localhost` | `(deny network*)` and `(allow network* (remote ip "localhost:*"))` | `none` refuses 127.0.0.1 and 1.1.1.1; `localhost` allows 127.0.0.1 only |
| What a sandboxed spawn costs | 300 runs each, `bash -c true` | 2.9 ms → 10.2 ms with our 12-rule profile; 9.9 ms with an **empty** profile. The cost is `sandbox-exec`, not the rules |
| A launcher calling `sandbox_init_with_parameters` then `execv` (ADR-0020's candidate) | the same loop | 11.3 ms against 10.8 ms: no faster. The time is `sandbox_init`, not the extra process. **Rejected** |

Three further ways round a path rule exist in the in-process checks and are closed there (and tested): a
dangling symlink into a protected directory (writing it creates the target), `..` after a name that does not
exist yet (the kernel would fail it), and a path that cannot be resolved.
