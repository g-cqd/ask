---
status: not-started
blocked-by: []
date: 2026-11-12
---

# 0226 — Copilot through the Copilot SDK, before VS Code's Local harness goes (February 2027)

Owner (2026-11-12, note n69): support the Copilot SDK and its harness, because the local variant is deprecated in February 2027; first
the research that explains every way it affects ask, then the whole integration in stages. The report:
`development/research/copilot-sdk-2026-11.md` (also in the owner's ~/Public).

## What was found

- VS Code 1.146 deprecated the Local harness; it is frozen now and removed in February 2027. The Copilot harness, the Copilot CLI's
  runtime driven through the Copilot SDK (becoming the Microsoft Copilot SDK), has been the default since 1.143.
- ask's Copilot account presents itself as that Local harness: VS Code's OAuth client, `copilot_internal` token, `vscode-chat`
  integration and VS Code's versions on direct model calls. Nothing announced closes that path; its official user leaves.
- The SDK is JSON-RPC (Content-Length framing, as LSP and MCP) to the runtime as a child process, or in process through a C ABI
  (experimental); no Swift SDK. It takes ask's tools and prompt (`tools`, `availableTools`, `systemMessage: replace`), asks
  permissions through a callback, and owns the loop, the session store and the compaction. The CLI's licence allows bundling it
  unmodified inside ask.

## Stages

0. A weekly probe of today's Copilot path, and a plain message when the Copilot account fails.
1. A Swift JSON-RPC client for the runtime over stdio, with ask named in its client info: models, a session, a prompt and its events,
   abort; probed live.
2. Option A: a Copilot harness lane in ask (its own tools; its permission requests in ask's approval prompt).
3. Option B: a provider whose loop is the runtime's, calling ask's tools with ask's prompt; measured against today's path; an ADR for
   the session mirror.
4. Optional: the in-process C ABI, against the cold-start and memory budgets.
5. Before February 2027: the old path kept, off by default, or removed.

## For the owner

A or B or both; the CLI installed or bundled; the CLI's login or an ask OAuth app; the old path's future; which GitHub account.

## Owner (2026-11-12)

- Both A then B, now, with the Copilot runtime fetched at build time: a pinned, checksummed Copilot CLI shipped beside ask (its
  licence allows unmodified copies only, so it cannot be built from source).
- ask stays a harness of its own too: its Copilot account mimics the new VS Code exactly (what VS Code's Agent Host sends through
  the runtime, recorded from the runtime and followed release by release, as 0193 does), and keeps the old Local harness mimic as a
  second variant ("keep supporting both"), until it breaks.
- Sign-in: ask's own GitHub OAuth app (the owner registers it), and the VS Code mimic's sign-in as well.
- Account: whichever the person signs in with.

## Order

1. Record what the runtime sends to CAPI (sign-in, token, headers, client identity), from the pinned CLI in a sandbox; the new mimic
   as a variant of `CopilotClient`, the old one kept; a choice between them.
2. The pinned runtime fetched by the build (version, checksum, licence beside it).
3. The Swift JSON-RPC client (stage 1), then A (stage 2), then B (stage 3).
4. ask's OAuth app sign-in once the owner has registered it.
