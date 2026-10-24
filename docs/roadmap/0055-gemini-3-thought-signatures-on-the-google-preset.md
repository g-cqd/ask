---
status: not-started
blocked-by: []
date: 2026-10-24
---

# 0055 — Gemini 3 thought signatures on the `google` preset

Reported from reading ask's source and pi-integrations' fix `704928a`; **not probed**. The `google` preset
(`Sources/AskAI/OpenAICompatible/ProviderPreset.swift`, `https://generativelanguage.googleapis.com/v1beta/openai`, `GEMINI_API_KEY`) reaches
Gemini through its OpenAI-compatible endpoint. Gemini 3 and later are reported to refuse a replayed tool call that has no thought
signature (HTTP 400 `INVALID_ARGUMENT`, "Function call is missing a thought_signature"). Checked in this repository by reading:

- `OpenAIWireChunk.ToolCall` decodes only `index`, `id` and `function`, so any `extra_content` on a streamed tool call is dropped.
- `OpenAIRequestEncoder` re-sends tool calls without it, and `RequestBlock.toolCall(id:name:input:)` has no slot for a signature.
- No file in Sources, Tests or docs mentions `thoughtSignature`, `thought_signature` or `extra_content`.

## Probe first

With a real `GEMINI_API_KEY` (not set on the development machine at the time of writing) and a Gemini 3 model: a two-round tool loop through
`ask --provider google`. If the second request returns "missing a thought_signature", the gap is confirmed; if it works, record that and close
this entry. Do not infer it from the report.

## If confirmed

Decode `tool_calls[].extra_content.google.thought_signature` in the wire chunk and keep it with the call; re-emit it as
`extra_content: {google: {thought_signature: ...}}` when the assistant turn is re-sent; where it is missing, send the documented sentinel
`skip_thought_signature_validator` only for Gemini 3 or later on this preset, only on the first call of a turn, never over a real signature.
The storage choice is shared with roadmap 0052 (a provenance marker on the thinking block, ADR-0033, or a field on the call) and should be
decided once. Other OpenAI-compatible presets do not take `extra_content` and must not change.
