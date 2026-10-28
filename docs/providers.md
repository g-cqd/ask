# Providers and accounts

You don't need to configure anything to start. When nothing names a provider, ask uses the first that can answer: Claude, then Codex, then
Antigravity, and Apple's on-device model when nothing is signed in.

## Signing in

| | Command |
|---|---|
| Claude subscription | `ask login claude` |
| Claude API key | `ask login claude --api-key` |
| ChatGPT subscription (Codex) | `ask login codex` (`--device` on a machine with no browser) |
| OpenAI API key | `ask login codex --api-key` (stored as provider `openai`) |
| Google account (Antigravity) | `ask login agy` |
| Spettro, Mistral Vibe | `ask login spettro`, `ask login mistral-vibe` (the browser sign-in issues a key) |
| A known service with an API key | `ask login groq`, `ask login openrouter`, … |
| Any OpenAI-compatible server | `ask login custom NAME URL` |

Inside ask, `/login` does the same without leaving; a key you type there is hidden and kept out of the conversation. `ask logout NAME`
forgets one sign-in, and `ask logout` forgets them all.

Claude also reads `ANTHROPIC_AUTH_TOKEN` (a bearer token for a gateway), `ANTHROPIC_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` from the
environment, in that order. A known service's key is read from its usual variable, such as `GROQ_API_KEY`.

## Choosing the model

- Inside ask, `/model` lists every model of every account you are signed in to; choose one and the thinking levels it accepts are offered
  next. `/model NAME` sets one directly.
- From the shell, `ask --provider NAME --model ID`, or `model` and `provider` in [configuration](configuration.md).
- `ask models NAME` lists what a provider offers, with its context window and output limit. Models ask cannot use (image, audio, no tool
  calls) are left out; `--all` shows them with the reason.

## Two accounts of one kind

Sign in a second account under a name of your own, then use that name as the provider:

```sh
ask login codex --name work
ask --provider work
```

`ask connections` lists them, with `rename` and `remove`. `ask connections alias work fast MODEL-ID` gives a model a short name
(`--model fast`). A session remembers which account it used, and ask never moves a conversation to another account on its own.

## Your own server

Any server that speaks OpenAI chat completions (llama.cpp, MLX, Ollama, LM Studio, vLLM, a gateway) can be added in
`~/.config/ask/providers.json`:

```json
{
  "default": "local",
  "providers": {
    "local": {
      "api": "openai-completions",
      "baseUrl": "http://127.0.0.1:8182/v1",
      "apiKey": "$LOCAL_KEY",
      "models": [{ "id": "my-model" }]
    }
  }
}
```

`"api": "openai-responses"` is for servers that speak the Responses API instead. `apiKey` names an environment variable; ask never sends a
key over plain `http` to another machine. `ask models local` refreshes the model list and the limits the server reports.

For Ollama, start it with `OLLAMA_CONTEXT_LENGTH=32768`: its default window can be as small as 4,096 tokens.

## Thinking

`thinking` (`--thinking`, `/thinking`, `ASK_THINKING`) asks for `off`, `minimal`, `low`, `medium`, `high`, `xhigh` or `max`. ask sends only
what the model says it accepts, and refuses a level it lacks rather than quietly picking another. `default` leaves it to the provider.
