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
