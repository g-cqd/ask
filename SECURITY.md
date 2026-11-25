# Security policy

`ask` runs a language model's tool calls inside a macOS Seatbelt sandbox by default and keeps provider credentials
(API keys, OAuth tokens from `ask login`) in `~/.config/ask` (mode `0700`/`0600`, or encrypted in the session vault).

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's **Report a vulnerability** button on the Security tab — never in
public issues or pull requests. Include:

- The `ask` version (`ask --version`).
- The sandbox & approval configuration (`--no-sandbox`, `config.json`, organisation policy if any).
- A minimal reproduction (command line, prompt/tool input, MCP server payload, or crafted media file).

Reports that reach a secret store (`~/.aws`, `~/.gnupg`, Keychains, `~/.netrc`, SSH private keys, `~/.config/ask`, or
sibling browser/app stores) or bypass session approval grants are treated as high severity.

## Response targets (best-effort, solo maintainer)

This project is maintained by a single developer on a best-effort basis; the targets below are realistic guidelines
rather than contractual SLAs:

| Milestone | Best-effort target |
| --- | --- |
| Private acknowledgement | Within **7–14 days** |
| Initial triage & severity confirmation | Within **30 days** |
| Fix & advisory — **Critical** | Within **30 days** (sooner when actively exploited) |
| Fix & advisory — **High** | Within **60–90 days** |
| Fix — **Medium / Low** | Next scheduled release, as time permits |

Security fixes in released versions are published with a GitHub Security Advisory (and CVE identifier where applicable)
and named in the release notes.
## Release verification

Every official `ask` tag release is built in CI, Developer ID signed, hardened-runtime protected, Apple-notarised, and
accompanied by SHA-256 checksums, a CycloneDX 1.5 SBOM (`ask-<version>.sbom.cdx.json`), and GitHub SLSA Build
Provenance attestations (`gh attestation verify <asset> --owner g-cqd`).
