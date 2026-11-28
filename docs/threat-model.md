# Threat Model (as of 2026-11-25)

Status: **accepted** (consolidates ADRs 0020, 0035, 0043, 0045, 0054, 0085, 0099, 0106, 0111, 0115, 0153, 0154, 0168
and `docs/sandbox.md`; aligned with OWASP Top 10 for LLM Applications 2025 and OWASP Agentic AI Threats).

## 1. Assets

| # | Asset | Where | Primary protection |
|---|---|---|---|
| D1 | Provider API keys & OAuth tokens | `~/.config/ask`, Keychain, `SessionKeys` | `0700`/`0600` files, Seatbelt read denial, `CommandEnvironment` withholding |
| D2 | User files, SSH/GPG/cloud secret stores & sibling app stores | `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, Sunset/Safari/Chrome stores | Seatbelt default-deny rules (`SandboxProfile`) |
| D3 | Session transcripts & reload grants | `~/.local/state/ask` (sealed vault when enabled), `SessionGrants` | Argon2id (64 MiB, t=3, p=4) + AEAD; reload grants `O_EXCL \| O_NOFOLLOW` `0600` |
| D4 | Human approval integrity | `ApprovalPolicy`, `CommandWords`, `CallGrants` | Conservative classifier, env scrubbing, grants disabled when `--no-sandbox` |
| D5 | Terminal & display integrity | Local TTY / TUI | `TerminalTextFilter` / `OutputEscapes` strips CSI/OSC/DCS escapes (incl. OSC 52) |
| D6 | Gateway node, server & shell-signing keys | Keychain (`gateway/*`), `trusted.json`, `nodes.json` | Non-file Keychain keys, `0700`/`0600` trust lists, end-to-end Noise `XX`/`IK`/`N` (ADR-0170) |

## 2. Adversaries

- **A1 — Untrusted content read by the model:** repository files, git history, issues, fetched web pages, tool stdout,
  MCP server responses (prompt injection vector, OWASP `LLM01` / `ASI01`).
- **A2 — Misled or hallucinating model:** proposes dangerous shell commands, path traversals, SSRF URLs, or unbounded
  action loops (`LLM06` / `LLM10` / `ASI02` / `ASI08`).
- **A3 — Untrusted repository metadata:** `.ask/config.json`, project skills, project agents, project MCP servers
  (`LLM03` / `ASI06`).
- **A4 — Malicious or compromised MCP server:** attempts SSRF on discovery, tool-name spoofing, or deceptive tool
  descriptions (`ASI02` / `ASI03`).
- **A5 — Compromised ACP editor client (`ask serve`):** controls `cwd` and requests MCP servers on stdio (`N-A4`).
  **Trust assumption:** the ACP editor process runs as the same user and is trusted to choose the workspace, but
  client-supplied MCP servers remain subject to `ask`'s sandbox, approval gates, and organisation policy.
- **A6 — Local same-user process & network adversary:** attempts symlink/TOCTOU races (`ScopedFile`), localhost tunnel
  hijacking (`ProviderProxy`), DNS rebinding (`FetchAddress`), or MITM.
- **A7 — Untrusted relay / compromised gateway or LAN peer (ADR-0170):** observes or tampers with traffic through
  Cloudflare or the gateway, probes the LAN nodes port, or attempts to serve modified web shell assets.

## 3. Trust Boundaries & Controls (OWASP LLM 2025 + Agentic AI)

| Threat | OWASP | Boundary | Current control | Gap / planned work |
|---|---|---|---|---|
| Prompt injection escalates a session grant | LLM01, LLM06, ASI02 | Model ↔ `bash` | `CommandWords` refuses assignments (`GIT_CONFIG_*`, `PATH=.`), `$` outside single quotes (`${x@P}`), redirections, runners, code-exec flags; `CommandEnvironment` withholds hijack vars; grants disabled under `--no-sandbox`; Seatbelt confines execution | — |
| Credential or secret-store exfiltration | LLM02, ASI03 | `ask` ↔ commands/disk/net | Seatbelt blocks `~/.ssh`, `~/.aws`, `~/.gnupg`, Keychains, sibling browsers, `~/.config/ask`; `CommandEnvironment` withholds credentials; `ProviderProxy` restricts tunnels to active commands | Private per-session `TMPDIR` (`MED-07`) |
| SSRF / DNS rebinding via `fetch` or MCP discovery | LLM06 | `ask` ↔ network | `FetchAddress` refuses loopback/private/link-local/metadata in every IPv4/IPv6 spelling and re-validates after DNS resolution | — |
| Symlink / TOCTOU redirect out of workspace | ASI03 | `ask` ↔ disk | `ScopedFile` uses `O_NOFOLLOW`, `F_GETPATH` verification, `openat`/`mkdirat` (`0755`/`0644`), atomic `renameat` + fsync | — |
| Malicious `.ask/` config, skill, agent, or MCP server | LLM03, ASI06 | Repo ↔ `ask` | `ProjectTrust` / `TrustedFile` binds project config, skills, and agents to explicit human approval by SHA-256 digest; project MCP servers run sandboxed | Extend `ProjectTrust` prompt to ACP-supplied MCP servers (`N-A4`) |
| Hostile image, PDF, or video triggers decoder memory bug | LLM05 | `ReadTool` ↔ media frameworks | Size limits, verified private copy (`ScopedFile.withCopy`), and isolated zero-network/zero-env `sandbox-exec` child (`ask decode-media`, `MediaDecodeHost`, N-A2) | — |
| Terminal escape injection (OSC 52 clipboard, title spoofing) | LLM05 | Model/tool ↔ TTY | `TerminalTextFilter` / `OutputEscapes` strips CSI/OSC/DCS before rendering | — |
| Unbounded spend / runaway loops / memory OOM | LLM10, ASI08 | Model ↔ runtime | Turn limits, byte caps, budget tests, organisation policy caps (ADR-0168) | Bounded default `ui.historyLimit` / `jobs.keepFinished` (`N-A7`, Sprint 2) |
| Release supply-chain tampering | LLM03 | CI ↔ users | Revision-pinned SwiftPM + `Package.resolved`, SHA-pinned Actions (`zizmor` 0 findings), Developer ID + notarisation + CycloneDX SBOM + SLSA provenance via `swift-ci` | Configure protected `release` Environment secrets on `g-cqd/ask` (`N-A6`) |
| Compromised gateway, tunnel or LAN peer on web access (ADR-0170) | ASI03 | Browser ↔ gateway ↔ node | Two separated doors (LAN IP + CIDR for nodes, `127.0.0.1` + RS256 `Cf-Access-Jwt-Assertion` for controllers); Noise `XX` pinned keys on LAN; end-to-end Noise `IK` channels and Noise `N` `SealedList`; Ed25519-signed `ShellManifest` pinned by Service Worker + strict CSP; `policy.gateway*` | WebAuthn passkey PRF unlock (deferred) |

## 4. Accepted residual risks (with review expiry)

| Risk | Owner | Mitigation today | Review / expiry date |
|---|---|---|---|
| `N-A2`: Media decoders run in main process | Maintainer | Closed (`ReadTool` delegates image/PDF/video decoding to zero-network, zero-env `sandbox-exec` child `ask decode-media`) | 2027-02-25 |
| `MED-07`: Commands share macOS `TMPDIR` | Maintainer | Closed (`JobTable` creates private `0700` `TMPDIR` for sandboxed commands; macOS `/private/var/folders` remains writable in Seatbelt for Foundation tools) | 2027-02-25 |
| `N-A4`: `ask serve` trusts ACP client's `cwd` & MCP server list | Maintainer | Stdio-only; ACP-supplied MCP servers are sandboxed by default (`definedByProject = true`) | 2027-02-25 |
| `MED-10`: User-named MCP servers run outside Seatbelt by design | Maintainer | Explicit user configuration required; project-supplied servers stay sandboxed (ADR-0099) | 2027-02-25 |
