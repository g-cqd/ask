---
status: done
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

## Not covered yet (covered 2026-10-31, run 2 below)

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

## Owner (2026-10-29): the default write scope is the workspace

Done: with no `sandbox.write` set, tools and commands write in the workspace, temporary directories, and the caches builds write
(`SandboxPolicy.developerWrites`: `~/Library/Caches`, where a `.build` linked out of the project lands, Xcode's DerivedData, SwiftPM's
two directories); not toolchains or `~/.cache`. `write: "anywhere"` or `--write anywhere` opens it. Checked through the release binary
with a home under `/Users/Shared`: a write in the project works, one to `$HOME` is refused, one under `~/Library/Caches` works, and a
real `swift build --disable-sandbox` of a package completes. The verbose sandbox line says "the build caches" rather than a path per
home: the long line pushed a resumed conversation off the screen (interactive probe D and H). The setup questions (gh, docker, `git push
-u` needing allowances) wait for roadmap 0155.

## Still owed (2026-10-30, close-out pass)

The default write scope is the workspace (done, `175c674`). Owed: finding 5 (`ask -p` passes control sequences, OSC 52 among them, to
the terminal), the hardening notes above, the default network (to decide with the owner), and a `standard` audit run over the result.

## Done (2026-10-30): finding 5

Validated: on the build of the morning, `ask -p` wrote a model's `ESC ] 52 ; c ; … BEL` (a clipboard write) and colour sequences to
standard output as they came. `TerminalTextFilter` now removes every escape sequence whole (CSI, OSC, DCS, SOS, PM, APC, two-byte
escapes, their 8-bit forms) and drops the other controls but tab and line feed; it keeps its state across streamed deltas, and a line
feed or 4,096 scalars end a sequence that never ends. The answer goes through it, and every line on standard error. The interactive
screen was already safe: TerminalKit's screen buffer replaces control characters with U+FFFD. Tests: `TerminalTextFilterTests` (red
first); `probe-agent-run.py` section Z, red on the morning's build.

## Hardening notes, reviewed (2026-10-30)

- **0700 session directories: done.** The session files were already 0600 and the output directory 0700, but the session directories,
  `sessions` and `ask` were 0755, so any user of the Mac could list which projects were worked on. `SessionDirectory.create()` makes
  them 0700 and tightens older ones when a session is next written. Tests: `SessionDirectoryPermissionsTests`.
- **The Keychain: done** (0110), pending the owner's signed build.
- **A default withhold list for well-known credential variables: for the owner.** `CommandEnvironment` withholds only the variables ask
  reads its own credentials from, by design ("a person's own variables are theirs to withhold"); withholding `GITHUB_TOKEN` or `AWS_*` by
  default would stop the model's `gh` and `aws` commands. `environment.withhold` already lets the person add them.
- **`/reload`'s self-check of a build the model could have written: for the owner.** The model may write in the build caches (the
  default write scope), so it could replace the binary `/reload` checks and starts. Comparing the new build's code signature with the
  running one's would close it for signed builds (0110); unsigned builds have nothing to compare.
- **The default network, still for the owner:** `"any"` today.


## Owner (2026-10-31): the open hardening notes

- **Default network: stays `"any"`.** The owner also wants a limited level: commands may reach only the model provider's server,
  alongside the existing levels. The macOS sandbox allows every host or none, so that level goes through the local proxy (0021).
- **Default withhold list: yes.** Commands no longer get well-known credential variables by default: `GITHUB_TOKEN`, `GH_TOKEN`,
  `AWS_*`, `OPENAI_API_KEY`, `NPM_TOKEN` and similar. `environment.pass` lets one back in, and the docs say why `gh` or `aws` then
  fail.
- **`/reload` signature check: yes**, with every build signed (0110). `/reload` refuses a new build whose signature is not the
  running one's.

## Done (2026-10-31): the default withhold list

`CommandEnvironment.wellKnownCredentials`, in `CommandEnvironment+WellKnown.swift`, holds about forty exact names. A run's policy
withholds them along with ask's own credential variables. `environment.pass` lets one back in, and `CommandEnvironment.inherit` (the
library's default) still withholds nothing.

- **AWS: exact names, not the `AWS_*` prefix.** The list has `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` and
  `AWS_SECURITY_TOKEN`. `AWS_REGION` and `AWS_PROFILE` are not secret, and an `aws` command with a profile in `~/.aws` keeps
  working. Credentials in files such as `~/.aws` and `gh`'s keychain entry are not environment variables, so this list does not
  cover them; the sandbox's secret-store protection does.
- Test: `WellKnownCredentialTests`, written first and red.
- Docs: the `environment` table in `configuration.md` and the setting catalog's default, which regenerates `config.example.jsonc`.

## Done (2026-10-31): the `/reload` signature check

`BuildSignature` in AskTools. A running build signed with a team's identity reloads only into a build that meets its own designated
requirement: `SecCodeCopySelf`, then `SecStaticCodeCheckValidity` of the new file, all architectures, strict. That requirement names
the signing certificate, not the code, so every rebuild signed the same way passes, and anything else at the executable's path is
refused before the self-check would start it. The notice says why, and that `Scripts/build-release.sh` builds and signs.

A running build with no team identifier (ad hoc, as `swift build` makes) has nothing to compare, so the reload goes on with a notice
saying so; refusing every unsigned rebuild would end `/reload` for unsigned use.

- Tests: `BuildSignatureTests`, on copies of `/usr/bin/true` signed ad hoc under chosen identifiers (signing ad hoc needs no
  keychain). `Scripts/mutate-changed.sh`: 10 of 10 mutants killed.
- Probes: the reload sections H, H2, H3 and I pass, on unsigned builds.
- Docs: the `/reload` row in `screen.md`.
- Not verified: a reload between two builds signed with the personal identity. That needs the first signing, the owner's one-time
  "Always Allow" (0110).

## Done (2026-10-31): the check, on signed builds

Probe H4 (`probe_reload_signed`, which needs `ASK_SIGNING_IDENTITY`) found the check passing everything. `runningRequirement()` read
the running build's signature from its executable's file, and `/reload` runs only once a new build has replaced that file. A signed
ask therefore saw the ad-hoc build's signature, took itself for unsigned ("The running build is not signed…"), and reloaded into it.

- `LaunchSignature` reads the signature once, off the launch path, when the interactive screen starts. `/reload` waits for that read.
- `BuildSignature.readRunning()` checks the running code against its file after reading (`SecCodeCheckValidity`). A mismatch is
  `.unreadable`, which refuses every build, never `.unsigned`.
- Tests: `BuildSignatureTests`, written first and red: an unreadable running signature refuses, and the launch read is the running
  build's.
- Probe H4, on a signed build: an ad-hoc build is refused before it runs; a build signed the same way reloads into the session, with
  no unsigned notice. Section I now installs ad-hoc builds, so its broken build still reaches the self-check. H, H2 and H3 pass
  signed.

Open: the "Not covered yet" audit (TLS and endpoints, the extension host, skills, the media and session parsers, supply chain).

## Done (2026-10-31): the Not-covered audit (run 2)

`development/research/security-audit-2026-10-31.md`. Partial as run 1 was: one agent, no separate verifiers. Six findings, each
reproduced and fixed test first:

1. Medium: the signed build had no hardened runtime, so an inserted library ran as ask and could read its Keychain items.
   `sign.sh` now passes `--options runtime`.
2. Medium: a project skill or skills root linked outside the project was loaded once trusted. It is now skipped with a notice.
3. Low–Medium: a session record's `write: anywhere` widened the default workspace on resume. A record now keeps only the scopes
   that narrow.
4. Low: `providers.json` headers went over plain http to another machine. Any header now counts as a credential.
5. Low: an unbounded PDF page spec with a quadratic repeat check. It is now capped at 10,000 pages, with a set.
6. Low: a video claiming an enormous length trapped converting its frame count. The count is clamped.

Builds also use `--force-resolved-versions`. For the owner: whether skill trust should digest the whole skill folder (the report's
hardening notes). The limited network level the owner asked for is 0021's. Nothing else of this record stays open.
