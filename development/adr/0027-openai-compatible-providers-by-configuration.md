---
status: accepted
date: 2026-10-19
---

# 0027 — Any OpenAI-compatible server is a provider, by configuration

## Context

`ask` spoke one protocol, Anthropic's. Local models (llama.cpp, MLX, Ollama, LM Studio, vLLM) and most hosted
gateways speak OpenAI chat completions. Roadmap 0026 asked whether the neutral seam (`ModelRequest` in,
`ModelEvent` out) would take a second protocol without widening, and pi answers the configuration question
with `models.json`: an endpoint that speaks a known API needs a file, not code.

## The probes

Ledger in `development/diary/2026-10-19-13.md`. What decided this:

- **"OpenAI-compatible" is a family of dialects.** The same model (Ornith-1.5-9B) on llama.cpp, MLX and Ollama
  streamed reasoning as `reasoning_content` or `reasoning`, tool arguments in fragments or whole, usage in a chunk,
  in a `chat.completion` object or in a chunk with no choices, and stray `""` or `"\n\n"` content around calls.
  The request side did not differ: all three accepted one shape, including `"content": null` beside `tool_calls`.
- **The seam held.** Every difference fits in the decoder; no neutral type changed. Recorded streams from all three
  servers are the decoder's test fixtures, byte for byte, replayed whole and in 7-byte pieces.
- **It works end to end.** `ask -p` passed four checkable tasks on each server (16 of 16), and the harder repeated
  suite on each model and runtime (diary 13).
- **One cross-provider bug** surfaced: reasoning from an OpenAI-compatible server has no signature, and Anthropic
  refuses unsigned thinking, so a session resumed on Claude would have failed. Fixed in the Anthropic encoder.
- **Ollama's default context is sized by memory** (4,096 tokens on this 16 GiB machine), and a longer request is
  refused with a clear 400, not truncated. `OLLAMA_CONTEXT_LENGTH` fixes it; probed both ways.

## Decision

1. `Sources/AskAI/OpenAICompatible` is the second provider. Its decoder absorbs observed dialect differences;
   **no compatibility switch exists for a difference nobody has observed** (pi's rule, adopted).
2. `~/.config/ask/providers.json` declares endpoints in pi's `models.json` vocabulary (`api`, `baseUrl`, `apiKey`,
   `headers`, `models[].id`, plus `default` and `defaultModel`), so an entry carries over. `--provider` chooses;
   `anthropic` is built in and reserved.
3. Keys are a literal or `$NAME`/`${NAME}`; an unset variable is an error. pi's `!command` keys are **not**
   supported: a configuration file that runs commands is a surface this change did not need.
4. A key over plain `http` to another machine is refused (ADR-0024's rule, now shared as `EndpointPolicy`); plain
   `http` without a key is allowed anywhere, since a LAN server has nothing to leak.
5. What both providers share is named once: `ProviderStream` (send, reject, frame, decode, truncate),
   `ProviderStreamError<DecoderFailure>`, and the `ModelEventDecoding` protocol each decoder implements.

## Consequences

- A new OpenAI-compatible endpoint is a few lines of JSON. A provider with its own auth (Spettro's browser
  sign-in, roadmap 0010) still needs code, but only for auth: the wire protocol is done.
- Reasoning is not sent back to OpenAI-compatible servers (no standard field, none of the three needs it).
- Usage `input` excludes cached prompt tokens for both providers, so the figures mean the same thing.
- Not covered: OpenAI's own API and hosted gateways were not probed (no key); the Responses API is not spoken.
