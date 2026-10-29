# Security audit of ask — run 1 (2026-10-29; files in ~/security-audits/ask/run-1)

Profile **quick**, scope the whole of `Sources` at `b952e7c`, method of `secure-coding`'s audit workflow (adapted from Cloudflare's
security-audit skill). **Partial:** one agent played reconnaissance, hunting and verification, so no candidate was verified by someone who
did not find it; the critic pass was the same agent's. Sandboxed source-and-local-only: every local check ran ask's own release build
against a fake provider on 127.0.0.1, with a scratch HOME and dummy secrets; nothing was sent to a provider or a shared service.

## Posture

The engineering of each control is careful: sandbox paths cannot inject rules, the file tools cannot be redirected between check and use,
project files cannot widen anything or read the environment into servers, the sign-in callback checks state, credentials are 0600, the
screen drops control sequences. The weakness is the **default policy**, not the mechanisms: a model that follows injected instructions
can, with no approval, write files that run later outside the sandbox, read credentials the five-entry denylist does not name, and send
them anywhere. The strict modes close most of that, except git hooks.

## Confirmed

| Severity | Finding | Observed |
|---|---|---|
| High | By default a command can plant code that later runs outside the sandbox (launch agents, shell startup files, git hooks, ssh config) | written under the default sandbox, beside a denied `~/.aws` read |
| High | Other tools' credentials are readable and the network is open by default | a dummy GitHub CLI token read, in both modes |
| High | Under `--write workspace`, git hooks can still be written | `.git/hooks/pre-commit` written |
| Medium | An MCP tool without annotations runs without approval, though the specification's default is destructive | source: approval only for `destructiveHint == true`; schema 2025-06-18: default `true` |

Details, reproductions and fixes: `findings.json` (validated).

## Needs validation

| Lead | Blocker | Check |
|---|---|---|
| `ask -p` writes the model's control sequences to a terminal (OSC 52 seen in stdout) | whether the person's terminal acts on them | run the probe's print-mode case in that terminal and look at the clipboard |

## Hardening notes

- Variables the person exports (`GITHUB_TOKEN`, `AWS_*`) reach the model's commands; withheld only if configured (ADR-0106's choice). A
  default withhold list for well-known credential variables would match the read protections.
- Session directories are 0755: other accounts can list project names (files are 0600).
- API keys and tokens are in a 0600 file, not the Keychain: any unsandboxed process of the person can read them (roadmap 0110).
- `/reload` runs the new build's self-check outside the sandbox; a build directory the model can write makes that a variant of the first
  finding.

## Good patterns seen

`SeatbeltProfile` (parameters, protections last, guarded ancestors), `ScopedFile` (descriptor-verified access), `ProjectTrust` (hash-bound
trust), `ConfigurationFile+MCP` (no `${NAME}` from a project), `LoopbackListener` (127.0.0.1, state, no echo), `CommandEnvironment`.

## Coverage

10 units: 4 candidate, 6 covered, none deferred (`coverage-ledger.json`, validated). Not covered in this run: the provider clients' TLS and
endpoint policy (ATS defaults, `ANTHROPIC_BASE_URL`), the extension host, skills' loading and trust, the image, PDF and video readers'
parsers (memory safety), the session file parser, and supply chain beyond pinned revisions. A `standard` run with separate verifiers
would cover them.
