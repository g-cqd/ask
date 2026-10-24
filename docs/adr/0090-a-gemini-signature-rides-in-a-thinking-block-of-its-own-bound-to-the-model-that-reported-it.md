---
status: accepted
date: 2026-10-24
---

# 0090 — A Gemini signature rides in a thinking block of its own, bound to the model that reported it

## Context

ADR-0080 showed live that Gemini 3 refuses a replayed function call with no thought signature (HTTP 400), that the documented sentinel is
accepted, and that Claude and GPT-OSS need the call's id on the result. The stream decoder and request encoder have to carry both, and
`RequestBlock.toolCall` has no field for a signature. This records where it lives, what was observed in real streams, and what a full tool
loop through the finished decoder and encoder did against the live account on 2026-10-24 under ask's own identity.

## The probes

- **Real streams** (12 captured, bodies kept outside the repository, six reduced into `Tests/Fixtures/Agy/`): lines are `data: {"response":
  {candidates, usageMetadata, modelVersion, responseId}, "traceId", "metadata"}`, CRLF-framed, and end with an empty text part that carries
  `finishReason: STOP`. **Observed.**
- **Gemini 3 Flash** sends a `thought` part with empty text first, then the call. Its `thoughtSignature` is 140 characters, on the **same part
  as the `functionCall`**, and on the **first call only** of a parallel pair (one pair observed). A text-only answer carries one on its **last text
  part**. **Observed**, one model.
- **Claude Sonnet 5.5 and GPT-OSS 120B** send no signature. GPT-OSS sends many non-empty `thought` parts; Claude sends empty text parts around
  its call. **Observed.**
- **`modelVersion`** equals the requested model id on all three families. **Observed**, three models.
- **Usage** is cumulative per chunk: `promptTokenCount`, `candidatesTokenCount`, `totalTokenCount`, and for GPT-OSS `cachedContentTokenCount`.
  `thoughtsTokenCount` was never present. **Observed.**
- **A full tool loop through the real decoder and encoder**, with the real eight tool schemas as `parametersJsonSchema`, on `gemini-3-flash`,
  `gemini-3.5-flash-lite`, `claude-sonnet-5-5-low` and `gpt-oss-120b-medium`: the first request produced a correct `read` call on all four; the
  history with its result got a correct answer on all four; a history with an **error** result got a 200 on all four. **Observed.**
- **The signature round trip**: the Gemini 3 history replayed with its signature, with it removed (so the sentinel stood in), and a
  `gemini-3-flash` history sent to `gemini-3.5-flash-lite` (another model's signature, so the sentinel again): all 200. That **accepts** each
  path; it does not show that the server checks the real signature rather than ignoring it. **Observed.**
- **An output limit of 200,000 on a model that reports 65,536** was accepted (200). **Observed**; ask therefore does not clamp.

## Decision

1. **Storage.** A call's signature is stored in a thinking block with empty text, immediately before the call it belongs to, behind
   the provenance marker `ask-foreign:gemini/<model>:<signature>` (ADR-0033, and the same pattern as the Responses reasoning of ADR-0062). No
   request or session type changes. An empty-text thinking block shows nothing in the transcript.
2. **Binding.** The marker names the model the stream reported in `modelVersion`; the encoder keeps a signature only when that equals the
   model being requested. A different or missing model sends the sentinel instead, which the live loop accepted.
3. **Encoding** (Gemini major version 3 or later, as `^gemini(-live)?-N` with N at least 3, ignoring case): a kept signature goes on the very
   part of its call; the first call of each model turn with none gets `skip_thought_signature_validator`; the sentinel is never put over a real
   signature; a later call keeps a real signature it has; a turn with no call has no signature. Other models never receive one, not even a matching one.
4. **Reasoning of any other kind is never sent**: thought text, Anthropic-signed or redacted thinking, and Responses items. A signature on a text part
   (observed on the last part of a text-only Gemini answer) is not captured either: it is optional, and its effect on quality is unprobed.
5. **Calls and results always carry the call's id**, and a result carries the call's name, looked up by id from the history; one with no known
   call is sent as `unknown_tool` rather than refused. Results come before the turn's text.
6. **Tools** are one group of `functionDeclarations` with the schema spliced in as `parametersJsonSchema`; the mode is `AUTO`. A result is
   `response: {output}` or `response: {error}`. Thoughts are asked for (`includeThoughts`) on every request.
7. **An explicit thinking control is refused** (`ThinkingError.unsupportedProtocol`): the model list reports `thinkingBudget`, `minThinkingBudget`,
   `thinkingLevel` and `supportsAdaptiveThinking`, and none was probed.
8. **Stop reasons**: `STOP` is an end of turn, or tool use when a call was made; `MAX_TOKENS` is a cut; the documented safety reasons are a
   refusal; anything else is kept as it came. Only `STOP` was observed. A prompt blocked in feedback is a refusal with a notice.
9. **Every message the server sends is cleaned** before a person sees it: control characters, including DEL and the C1 range, become spaces, and it
   is cut at 300 characters.

## Consequences

- If a server ever reports a `modelVersion` that differs from the requested id, signatures silently stop replaying and the sentinel stands in.
  Nothing tells the person, and the cost is quality, not correctness. **Open.**
- The sentinel goes on the first call of **every** earlier turn, not only the current one. Google documents validation for the current turn
  only; whether earlier turns need it is unprobed, and the live loop had one call.
- **Open:** a signature on a later parallel call (the pair observed had none), a signature split across events, whether replaying GPT-OSS
  thought text helps, an error event inside a 200 stream (the shape is assumed from the HTTP error body), a usage-limit refusal's wording, and
  what a `gemini-2.5` model reports (503, no capacity, again).
- The decoder reports a signature-only thinking block before every Gemini 3 call, so each such call adds one empty block to a stored session.
- Nothing here sends a request: the client, refresh, the provider and a connection kind remain (roadmap 0052).
