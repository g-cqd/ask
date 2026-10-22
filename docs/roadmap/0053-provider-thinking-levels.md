---
status: in-progress
blocked-by: []
date: 2026-10-21
---

# 0053 — Provider thinking levels

The thinking-setting part of 0043, tracked on its own so it can finish independently of native search tools. A level in
`config.json`, `ASK_THINKING` and `--thinking` must reach the request and be visible in the effective settings and screen.
An absent setting preserves existing wire behaviour; an explicit reset/default can override a lower layer.

## Execution contract

Research the actual controls first: run the reference client with intercepted payloads, then use ask's own credentials
for small requests with positive and invalid-parameter controls. Record only statuses, redacted errors and usage counts.
Do not guess that disabling is supported, map an unsupported level to a different level, or claim capability from a
static cross-account model list. No default inference is required to use the feature.

Then add the smallest request/configuration path the probes support. Validate provider wire shapes with red-first tests,
layer precedence and reload with deterministic tests, and the CLI with local fake servers. Show requested versus provider
validated/defaulted state honestly. Keep provider-specific mapping in AskAI, not in the generic loop or terminal package.

Finish with deliberate broken-rule tests, the release quality gate, interleaved shipping measurements, a decision record
and a fast-forward landing. Search tools and transcript folding are not part of this entry.

## Done

A level in `config.json`, `ASK_THINKING` and `--thinking` reaches native Claude, Codex and Responses requests, including tool
turns and compaction, and shows in `ask config`, the reload report and the status label (ADR-0060). Native Claude capability
discovery, authorization-scoped caching and `ask models anthropic` landed with it.

## Still open

- Live verification of the *finished* feature against the real accounts (only the research requests were live).
- Reload argument forwarding and cancellation during the deferred lookup have no executable tests.
- A lookup's own notices are not displayed.

- How a provider proves an "off" request can be honoured. The seven cached Codex models report no disabled effort.
- Generic OpenAI-compatible services do not all honour the same thinking field; do not silently promise portability.
