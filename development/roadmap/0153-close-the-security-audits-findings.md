---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0153 — Close the security audit's findings (run 1)

The owner asked for a full review of the security posture (2026-10-29). `development/research/security-audit-2026-10-29.md` is the
report; the validated `findings.json` and `coverage-ledger.json` are in `~/security-audits/ask/run-1`. The run was `quick` and partial:
one agent, no independent verifier.

## The findings, each to be fixed test first

1. **High: by default a command can plant code that later runs outside the sandbox.** Protect, for writes, every path that runs or is
   loaded later outside ask (launch agents and daemons, login items, shell startup files, all of `~/.ssh`, git hooks and the executable
   keys of `.git/config`, `~/.config/git`, crontab, ask's own executable); a write there asks the person. Decide whether the default write
   scope becomes the workspace.
2. **High: other tools' credentials are readable and the network is open by default.** Extend the protected reads to known credential
   stores (gh, docker, kube, npm, pypi, gcloud, azure, git-credentials, other agents' tokens, browser profiles); decide the default
   network (localhost, or asking for the first outbound host of a session, with 0021).
3. **High: under `--write workspace`, git hooks can still be written.** Deny `.git/hooks` and `.git/config` writes in every mode.
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
