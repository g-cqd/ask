# Thinking controls — 2026-10-21

Research for roadmap 0053 (the thinking-setting part of 0043). This is not an adopted provider capability table.

## Reference-client experiment

Reference: installed pi-ai release 1.3.0, `dist/api/anthropic-messages.js`, `openai-codex-responses.js`, and the flattened
chat-model exports. Run its actual `streamSimple` implementations, intercept `onPayload`, then throw before the network.
A fake fetch function also throws if reached; only dummy credentials are used, including a synthetic JWT account claim.

```sh
node docs/research/probes/pi-thinking.mjs /path/to/pi-ai/dist
```

The checked-in probe produces 24 payload summaries for Sonnet 5.5, Sonnet 4.6 and gpt-6.1-sol, including unset, valid levels
and out-of-contract strings. **Type distinction matters:** `SimpleStreamOptions.reasoning` accepts `ThinkingLevel`, whose
declared values are minimal/low/medium/high/xhigh/max. `ModelThinkingLevel` additionally has off. The direct calls with
`off`, `ultra` and `invalid` deliberately violate the former type: their fallback behaviour is not evidence of a pi UI bug.

Observed payloads, not live acceptance:

| Model | Unset | Valid explicit controls | Out-of-contract inputs |
|---|---|---|---|
| Sonnet 5.5 | Adaptive thinking, root effort high, a system-message effort marker high, binding controls | low/medium/high/max leave root effort high but change the **system-message `output_config.effort`** | off/ultra/invalid become high in this direct API call |
| Sonnet 4.6 | `thinking.type: disabled` | Adaptive thinking with root `output_config.effort` low/medium/high/max | off/ultra/invalid become high in this direct API call |
| gpt-6.1-sol | No reasoning member | `reasoning.effort` low/medium/high/max, summary auto | off/ultra/invalid clamp to low in this direct API call |

Thus reading only the root effort would falsely conclude that Sonnet 5.5 ignores every requested level. It carries the
active level in a system-message marker instead. Relevant pi betas are `mid-conversation-output-config-2026-07-01` and
`thinking-binding-controls-2026-08-01`; their acceptance by ask's account is not established by this experiment.

The seven models in ask's existing Codex cache report low/medium/high/xhigh/max and, on five, ultra. No model reports an
off/none effort. `ultra` being offered by the account does not make it a valid pi `ThinkingLevel`; copying pi's static level
vocabulary would lose it. A live catalog and native acceptance still need checking.

## Probe corrections, not provider facts

- The first export lookup selected `ANTHROPIC_CLASSIFIER_MODELS`, not `ANTHROPIC_MODELS`; its false "absent" results were
  discarded. The explicit chat exports contain 17 Anthropic and nine Codex entries.
- A plain dummy Codex key never reached payload capture: that client extracts an account id from a JWT first. Replaced
  with a **synthetic**, unsigned token containing a fixture account claim. No real token was read by the Node probe.
- The initial summary omitted system-message effort markers. Added those fields before interpreting Sonnet 5.5 output.

## Native checks (2026-10-22)

Ledger: `docs/diary/2026-10-22-07.md`. First-party requests used ask's own credentials; a separately opted-in call through
its existing Claude owner refreshed stale access once. This is not evidence of concurrent refresh safety (0044).

- **Codex gpt-6.1-sol:** low/medium/high/xhigh/max return 200, including summary auto; none and minimal are model-unsupported
  400. **Ultra is advertised by the catalog but rejected by the inference schema (400).** Do not copy every advertised
  level directly into a request or silently clamp one to another.
- **Sonnet 5.5:** adaptive low/high/xhigh/max return 200, invalid effort 400. Disabled returns 400, with a server explanation
  that the off spelling is `between_tools`; that spelling returns 200. Enabled/budget 1024 is accepted as compatibility,
  despite the catalog marking enabled unsupported; budget 1 is rejected as below 1024.
- **Sonnet 4.6:** disabled returns 200 and between_tools returns 400. Off mode is model-specific, not provider-wide.
- **Native catalog:** `GET /v1/models` returns 14 entries, `has_more: false`, context/output limits and thinking/effort
  capability flags. Prefer reported modes to a model-name guess, but do not treat them as absolute inference eligibility.
- **Continuation:** a real Sonnet 5.5 max-effort response contained one signed thinking block (163 reasoning tokens).
  Replaying it unchanged and switching the next completed turn to adaptive low or between_tools both return 200 with
  ordinary OAuth betas; no managed-effort beta was needed for these between-turn changes.
- **Tool round trip:** between_tools completed two fixture echo calls and a final answer across three requests, all 200.
  No process or file tool was executed, and this sample emitted zero thinking updates; the server's claim that short
  updates may appear is not a guarantee that every loop produces them.

Probes print statuses, sanitized parameter errors and counts, never response/signature text. They are diagnostic runs,
not unit gates. Native probe sources are retained under `probes/` as `.swift.txt` and removed from the ordinary test target.
No quality, cost-saving or latency conclusion follows from one tiny request per option.
