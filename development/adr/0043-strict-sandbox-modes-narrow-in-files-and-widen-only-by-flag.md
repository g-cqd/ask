---
status: accepted
date: 2026-10-20
---

# 0043 — Strict sandbox modes narrow in files and widen only by flag

## Context

ADR-0035 shipped the policy and its Seatbelt compiler with a write scope and three network levels, but nothing set
them. Roadmap 0042 asks for configuration keys, an honest display, and a strict run that can still build Swift.
The first probe found that a Swift build under any ask sandbox fails on an uncached manifest (diary 38); that is fixed
by telling the model to use `--disable-sandbox`, which this decision depends on.

## Decision

- **Keys.** `sandbox.write`: `"workspace"` (the directory ask was started in), `"anywhere"`, or a list of absolute or
  `~/` paths. `sandbox.network`: `"none"`, `"localhost"` or `"any"`. Other values are refused, naming the choices.
- **Every file narrows.** The defaults are the widest values, so each layer that sets a key can only narrow what is
  below it: write scopes intersect, the network takes the lower level. A trusted project may therefore set both, and
  cannot widen what the user's file set. This holds without asking which file is the project's.
- **Only flags widen.** `--write` and `--network` replace what the files say: a flag is the user at the terminal.
  They are refused beside `--no-sandbox`, carried across `/reload`, and reported as the sandbox's source.
- **Scratch stays writable**: `/private/tmp`, `/private/var/folders` (`$TMPDIR` and per-user caches) and the usual
  devices, as before. The workspace is canonicalized as the kernel spells it (`/private/var/…`).
- **Shown honestly.** The startup notices (and `ask -p` stderr) say where writes go and how far the network reaches;
  `ask config` shows the section and the effective writes/network; the status line adds `sandbox: workspace only`,
  `localhost only`, `no network`, or `no sandbox`. The default adds nothing.

## Probes

Real-binary probe N, with the user's file set to workspace and localhost: workspace writes work; bash and the write
tool cannot write to `/Users/Shared`; temporary directories can; a separate localhost server answers (HTTP 200); a
fresh Swift package builds and runs with `--disable-sandbox`; a trusted project narrows the network to none (curl
cannot connect, exit 7); a trusted project asking for `write: anywhere, network: any` widens nothing; the user's flags
widen both. Probe R checks the four status labels. Ten library and wiring mutations are caught (diary 39).

## Consequences

Tools that write outside the workspace (`~/.npm`, `~/.cache`, a global `go` cache) fail under `workspace`, with the
refusal note saying where writes are allowed. SwiftPM's user cache is unwritable and is skipped with a warning.
The scratch allowance is broad: `/private/var/folders` holds other per-user caches. Reads are still a deny list:
a read allow-list on a deny-default base, and recording the policy in the session, remain in roadmap 0042.
