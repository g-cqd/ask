# Research note — every way to connect ask to a model, October 2026

How Codex/OpenAI, Claude, Spettro and other OpenAI-like providers can be reached, from four sources read or probed
on 2026-10-19: pi-integrations (`~/Developer/pi-integrations`, the reference ADR-0007 named), pi 1.3.0's own
provider code and docs, the installed `codex` and `claude` CLIs' stored state (key names only, never values), and
unauthenticated probes of each endpoint. Decisions belong in ADRs; this note is the evidence they cite.

## What ask has today

| Provider | Way | Status |
|---|---|---|
| Claude | subscription OAuth (PKCE, pasted `code#state`) | built (ADR-0007, ADR-0018) |
| Claude | `ANTHROPIC_API_KEY` | built |
| Claude | gateway via `ANTHROPIC_BASE_URL` | built, https or loopback only (ADR-0024) |
| any OpenAI-compatible | `providers.json`, key from `$NAME` | built (ADR-0027) |
| local llama.cpp, MLX, Ollama | `providers.json`, no key | built and measured (research note on local models) |

## Codex and OpenAI

1. **ChatGPT subscription, Codex's own sign-in** (pi-integrations `codex`, pi's `openai-codex`):
   - client `app_EMoamEEZ73f0CkXaXp7hrann`, PKCE S256 against `auth.openai.com/oauth/authorize`;
   - browser callback on `127.0.0.1:1455/auth/callback` (the port the Codex CLI uses, so a pasted redirect URL is
     the fallback when it is taken), or **device code**: `POST /api/accounts/deviceauth/usercode`, user opens
     `auth.openai.com/codex/device`, poll `/api/accounts/deviceauth/token`, exchange at `/oauth/token`;
   - the access token is a JWT whose `https://api.openai.com/auth` claim holds `chatgpt_account_id`;
   - **refresh tokens rotate and are single-use**: a second client sharing one signs the other out;
   - inference is **not chat completions**: `POST chatgpt.com/backend-api/codex/responses`, the Responses API,
     SSE (pi can also use a WebSocket), headers `Authorization: Bearer`, `chatgpt-account-id`,
     `OpenAI-Beta: responses=experimental`, `originator`, `session-id`; body `store:false`, `instructions`,
     `input[]`, `include:["reasoning.encrypted_content"]`, `prompt_cache_key`, `reasoning:{effort,summary}`;
   - reasoning comes back as an item whose `encrypted_content` must be replayed whole on the next request; pi keeps
     the whole item as the thinking block's signature;
   - catalog `GET /backend-api/codex/models`, quota `GET /backend-api/codex/usage`;
   - not a published contract; pi-integrations marks it experimental and identifies itself honestly (`originator`).
2. **OpenAI API key** (`OPENAI_API_KEY`): `api.openai.com/v1` answers chat completions, which ask speaks today
   through `providers.json`; probed 401 with OpenAI's error shape. The Responses API (`/v1/responses`) is the same
   protocol as item 1 and is what reasoning models replay reasoning through.
3. **Reusing `~/.codex/auth.json`**: rejected. It holds `tokens` (rotating) and an `OPENAI_API_KEY` field; taking
   either is taking another program's credential, and the token would sign Codex out.
4. **Driving the `codex` binary** (`exec`, `app-server`, `mcp-server`): that delegates to Codex's agent, not to a
   model; out of scope for a provider.
5. **Azure OpenAI**: `api-key` header, deployment names, `api-version`; chat completions for Foundry models.

## Claude

Built: subscription OAuth, API key, base URL. Not built:
- `ANTHROPIC_AUTH_TOKEN` as bearer and `ANTHROPIC_OAUTH_TOKEN` (pi accepts both): environment-only, small.
- **Bedrock** (SigV4, or a bearer `AWS_BEARER_TOKEN_BEDROCK`) and **Vertex** (Google ADC): other transports and auth.
- Reusing Claude Code's keychain credential: rejected for the same reason as item 3.

## Spettro (pi-integrations `spettro`)

`POST {base}/auth/initiate` with a session id returns a browser link; poll `GET /auth/poll/{session}` (10 minutes
overall, 30 s a request) until it yields a **device API key** (no refresh). Inference is chat completions at
`{base}/v1` with `Authorization: Bearer` (probed: 401 `missing api key`, OpenAI's shape); catalog `GET /v1/models`
with `context_window`, `vision`, `reasoning`. `SPETTRO_API_URL` overrides the base. What ask lacks is the sign-in.

## Other OpenAI-compatible providers

Probed 2026-10-19 with an unauthenticated `GET /models` (or `POST /chat/completions`):

| Provider | Base URL | Key variable (pi) | Answer |
|---|---|---|---|
| OpenAI | `https://api.openai.com/v1` | `OPENAI_API_KEY` | 401, OpenAI shape |
| OpenRouter | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | 200, public model list |
| Groq | `https://api.groq.com/openai/v1` | `GROQ_API_KEY` | 401, OpenAI shape |
| DeepSeek | `https://api.deepseek.com/v1` | `DEEPSEEK_API_KEY` | 401, **plain text** |
| xAI | `https://api.x.ai/v1` | `XAI_API_KEY` | 401, `{"error":"…"}` |
| Mistral | `https://api.mistral.ai/v1` | `MISTRAL_API_KEY` | 401, `{"detail":…}` |
| Together | `https://api.together.xyz/v1` | `TOGETHER_API_KEY` | 401, **plain text** |
| Fireworks | `https://api.fireworks.ai/inference/v1` | `FIREWORKS_API_KEY` | 401, OpenAI shape |
| Cerebras | `https://api.cerebras.ai/v1` | `CEREBRAS_API_KEY` | 403, `{"detail":…}` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `GEMINI_API_KEY` | 400, error **in an array** |
| Moonshot | `https://api.moonshot.ai/v1` | `MOONSHOT_API_KEY` | 401, OpenAI shape |
| Hugging Face | `https://router.huggingface.co/v1` | `HF_TOKEN` | 200, public model list |

Error bodies come in six shapes; ask reads all of them (diary 14). Not probed: LM Studio, vLLM, Azure, Copilot
(token exchange), Kimi, MiniMax, Qwen, and models served with a key: none of these runs had one.

## Order proposed

1. Built-in presets for the table above: `--provider groq` works with `GROQ_API_KEY` set, no file needed.
2. `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_OAUTH_TOKEN`.
3. The Responses protocol, then Codex sign-in on it (browser and device code): needs provenance on reasoning blocks
   first, so a session moved between providers never sends one provider's reasoning to another.
4. Spettro sign-in.
5. Bedrock and Vertex, if wanted: transports and signing of their own.
