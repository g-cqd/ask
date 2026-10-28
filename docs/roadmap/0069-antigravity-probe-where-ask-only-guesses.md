---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0069 — Antigravity: probe where ask only guesses

`docs/research/antigravity-2026-10.md` registers what is known about Cloud Code and 22 things that are not. Five of them decide whether the connector
behaves well when something goes wrong, and each has a probe that can fail. The first four cost almost nothing; the fifth needs the owner.

## The work, cheapest first

1. **`MAX_TOKENS` (U6).** A request with `maxOutputTokens` of 8: does the stream end with `finishReason: MAX_TOKENS`, and does the loop show a cut answer
   rather than a finished one? Today `MAX_TOKENS` is mapped from Google's documented list and only `STOP` was observed.
2. **A longer tool loop and three parallel calls (U8).** Is the signature only on the first of three? Does a ten-turn Gemini 3 loop need the sentinel on earlier turns,
   or does it accept their omission (Google documents validation for the current turn only)?
3. **The thinking fields (U11).** `thinkingBudget`, `thinkingLevel` and `supportsAdaptiveThinking` are in the model list. Send each in `generationConfig.thinkingConfig`
   on `gemini-3-flash` and read what the usage and the thoughts do. If one works, ADR-0060's levels can extend to Antigravity; if none does, the refusal stays.
4. **The quota fields (U3).** Read `quotaInfo` before and after a measured amount of use on one model, and see which entries move. If the pools are what they look like,
   `ask models agy` can show what is left and when it lifts, and a usage limit can be told apart from a rate limit.
5. **A request longer than the window (U1)**, on `gpt-oss-120b` (about 140,000 tokens), **after the owner says yes**: record the status and the body. Then make the
   recognizer (`ProviderFailure.Kind.describesContextOverflow`) accept the observed wording **with the recorded body as its test**, and show the loop compacting and
   retrying on it. Do not widen the recognizer to a guessed wording first.

## Done when

Each of U1, U3, U6, U8 and U11 has a verdict in a diary with its probe, moves from the "not known" table of the register to the "known" one, and any code it changed has
the recorded body or stream as its fixture and a fault that fails without the change.

## Not claimed

That the refusal wording is the same for Claude and Gemini on Cloud Code: the first probe gives one family's. The others stay open.

## Owner answers (2026-10-28)

- **U1: yes** to the one request of about 140,000 tokens on `gpt-oss-120b` (step 5). Not yet sent.
- **U12: yes** to sending the first-party identity once, to measure the catalogue. Not yet sent.
- **U19:** applied to all providers as a setting, roadmap 0089.
- **U22:** not applicable.

## U1 result (2026-10-28)

One request, 137,838 tokens of random dictionary words, to `gpt-oss-120b-medium` (window 131,072) through the release binary: **HTTP 400, "The input (137838 tokens) is longer than the model's context length (131072 tokens)."** Answered in 3.6 s. `describesContextOverflow` did **not** recognise it (no "exceed", no "maximum context length"), so the loop showed a refusal instead of compacting. Fixed with that wording and a window pattern; test `the recorded Antigravity refusal for length...`. Not captured: the raw JSON body (the test assumes the usual envelope), and the compact-and-retry run against the live server (it would be a second large request). Step 5 of this entry is done except for that last demonstration; U12 is still to send.

## U1 second probe, and a thought-signature bug (2026-10-28)

The second large request to `gpt-oss-120b-medium` met two HTTP 503s, then ask compacted ("Compacted the conversation…"), and the
provider then refused: "The input (138295 tokens) is longer than the model's context length (131072 tokens)". ask stopped with
"does not fit … even after compacting". A single oversized user message cannot be compacted away; a fix (clip, or refuse early with
a clear message) is not done.

`gemini-2.5-flash` on Antigravity refuses any tool call, with or without an image: HTTP 400 "Function call is missing a
thought_signature in functionCall parts … `default_api:read`, position 2". ask sends the sentinel only for `gemini-3*`
(`AgyThoughtSignature.requiresSignature`). Not fixed; found while testing images (0084).
