# Administrator Hardening & Enterprise Policy Guide

Status: **accepted** (R-OPS-1, R-OPS-2, R-OPS-3; complements ADR-0168, `docs/sandbox.md`, and `docs/threat-model.md`).

## 1. Organisation Policy (ADR-0168)

Deploy an administrator-owned policy file at `/Library/Application Support/ask/policy.json` (root-owned, `0644`) or via
MDM managed preferences so individual users cannot weaken the security floor:

- **Forbid `--no-sandbox`:** ensures every command runs inside macOS Seatbelt and media decoding runs inside
  `ask decode-media` (`MediaDecodeHost`).
- **Forbid `--yes`:** requires human approval for non-granted tool calls.
- **Connection & model allowlists:** restrict `ask` to approved enterprise LLM endpoints and models.
- **Session vault encryption:** require Argon2id + AEAD encryption for stored transcripts under `~/.local/state/ask`.
- **Gateway controls (ADR-0170):** set `policy.gatewayAllowed: false` to forbid sharing sessions with a gateway on
  managed workstations; or keep sharing allowed while setting `policy.gatewayApprovals: false` (so tool/sandbox
  approvals can only be answered at the physical keyboard) and `policy.gatewayStart: false` (forbidding remote session
  creation).

## 2. Security Event Log (SIEM Export)

`AskAgentCore.SecurityAuditLog` writes bounded (1 MiB, rotated to `.1.jsonl`), `0600`, single-line JSONL records to
`$XDG_STATE_HOME/ask/security-audit.jsonl` (default `~/.local/state/ask/security-audit.jsonl`).

- **Recorded events:** `sandbox.approval`, `mcp.destructive_approval`, `tool.command_approval`, `tool.file_approval`,
  `tool.host_approval`, `tool.approval`, and gateway events (`gateway.trust`, `gateway.enroll`, `gateway.node`,
  `gateway.remote`, `gateway.viewer`, `gateway.shell`) with `outcome` and sanitized non-secret scope metadata (program
  names, host, MCP tool name, key fingerprints — never prompts, arguments, file contents, or keys).
- **Tamper resistance:** Seatbelt denies child commands write access to `$XDG_STATE_HOME/ask`.

## 3. Release Verification

Every official `ask` release ships:
1. Developer ID signature (`Identifier=ask`), Hardened Runtime, and Apple notarisation.
2. SHA-256 checksums (`ask-<version>-macos-arm64.tar.gz.sha256`).
3. CycloneDX 1.5 SBOM (`ask-<version>.sbom.cdx.json`) generated from `Package.resolved`.
4. GitHub SLSA Build Provenance attestations verifiable with:
   ```sh
   gh attestation verify ask-<version>-macos-arm64.tar.gz --owner g-cqd
   ```
