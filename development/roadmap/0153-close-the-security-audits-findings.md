---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0153 — Close the security audit's findings (run 1)

The owner asked for a full review of the security posture (2026-10-29). `development/research/security-audit-2026-10-29.md` is the
report; the validated `findings.json` and `coverage-ledger.json` are in `~/security-audits/ask/run-1`. The run was `quick` and partial:
one agent, no independent verifier.

## How the refinements behave (owner, 2026-10-29)

The sandbox refinements below are not plain denials: a call that reaches a protected path, a credential store, or the network beyond the
default goes behind **call approval with the confirmation tool** (0116's picker as the confirmation step, 0134's approval system), and
each protected set and default is **tunable in the configuration** (documented in `docs/configuration.md`, the person's own file only, as
`sandbox` already is). A model's command asks; the person decides once, for the session, or in config.

## The findings, each to be fixed test first

1. **High: by default a command can plant code that later runs outside the sandbox.** Protect, for writes, every path that runs or is
   loaded later outside ask (launch agents and daemons, login items, shell startup files, all of `~/.ssh`, git hooks and the executable
   keys of `.git/config`, `~/.config/git`, crontab, ask's own executable); a write there asks the person through the confirmation
   tool, and the list is tunable in config. Decide whether the default write
   scope becomes the workspace.
2. **High: other tools' credentials are readable and the network is open by default.** Extend the protected reads to known credential
   stores (gh, docker, kube, npm, pypi, gcloud, azure, git-credentials, other agents' tokens, browser profiles), a read there asking
   for approval, the list tunable in config; decide the default network (localhost, or asking for the first outbound host of a session, with 0021).
3. **High: under `--write workspace`, git hooks can still be written.** `.git/hooks` and `.git/config` writes ask for approval in every
   mode, tunable in config.
4. **Medium: an MCP tool without annotations runs without approval.** Approve unless `readOnlyHint == true` or the person allowed the
   tool; the start of 0134.
5. **Needs validation: `ask -p` writes control sequences to a terminal.** Check the owner's terminal; strip C0/C1 controls from text
   written to a terminal either way.

## Hardening notes

A default withhold list for well-known credential variables (`GITHUB_TOKEN`, `AWS_*`, ...), 0700 session directories, the Keychain
(0110), and `/reload`'s self-check of a build the model could have written.

## Not covered yet

TLS and endpoint policy of the provider clients, the extension host, skills' loading and trust, the image, PDF and video readers'
parsers, the session parser, supply chain beyond pinned revisions: a `standard` run with separate verifiers.

## Done (2026-10-29): finding 4

An MCP tool is asked about unless its server says it is read-only (`readOnlyHint: true`) or not destructive (`destructiveHint: false`),
as the MCP spec (2025-06-18) defines the defaults: `MCPToolAnnotations.needsApproval`, used by the direct tools and by `mcp_call`. The
question, the refusal and `mcp_search`'s mark now say "the server does not say it is read-only". The old tests that pinned "an unmarked
tool is never asked about" are replaced; the fixture server's harmless tools are marked read-only, as a real server's should be. A mutation
back to the old rule turns `MCPAnnotationApprovalTests` and `MCPApprovalTests` red; `probe-mcp.py` and `probe-mcp-screen.py` pass through
the release binary. `ask -p` still runs such a tool, since naming the server was the consent (ADR-0111). Consequence to watch: a server
that annotates nothing (the owner's apple-docs, lldb, xcode were not checked) now asks for each tool once per session.

## Done (2026-10-29): findings 1, 2 and 3 (ADR-0135)

Protections that ask: what runs later outside ask cannot be written, other tools' credentials cannot be read, and a call's request
for one is put to the person, who can allow it for the call or the session; `sandbox.allowWrite` and `sandbox.allowRead` open one for
good. Tests: `SandboxAskablePathsTests` (a mutation that lifts nothing turns it red), `SandboxAllowWriteTests`, `BashSandboxTests` under
the real `sandbox-exec` (a startup file, a launch agent and an existing repository's hook stay unwritten; `git init` in a fresh workspace
works; gh's token is unreadable). Through the release binary, `probe-interactive.py` section S2: a plain write to `$HOME/.zshrc` fails,
a request asks naming it protected, allowed it writes; a request for gh's credentials asks, denied nothing of the token reaches the model.
278 interactive checks and six other probes pass.

Still open: whether the default write scope becomes the workspace, and the default network (to decide with the owner); finding 5
(`ask -p` and terminal control sequences); the hardening notes; a `standard` audit run with separate verifiers.

