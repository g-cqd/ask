# Research note — local models for ask, October 2026

Measured on the development machine (Apple M2 Pro, 16 GiB, macOS 27.2). Evidence and method in
`docs/diary/2026-10-19-13.md`; the decision to support these servers is ADR-0027.

## What runs well here

| Runtime | Model | Speed (prompt / generate) | ask end to end |
|---|---|---|---|
| **MLX** (`mlx_lm.server`) | **Ornith-1.5-9B, 4-bit** | 168–176 / 26.6–27.3 t/s | fastest: median 34 s a task |
| llama.cpp (`llama-server --jinja`) | Ornith-1.5-9B, Q4_K_M | 201–206 / 16.7–19.5 t/s | median 62 s a task |
| llama.cpp | Gemma-4-E4B, QAT q4_0 | 379–389 / 36.0–36.3 t/s | median 90 s a task: more turns, despite faster tokens |
| Ollama (llama.cpp inside) | Ornith-1.5-9B, Q4_K_M | not benchmarked | passed; needs `OLLAMA_CONTEXT_LENGTH` |

Every configuration passed every task (34 runs). Raw token speed did not predict task time.

## Using one with ask

```sh
~/.models/serve-local-model.sh            # this machine's set-up: MLX, 127.0.0.1:8182
ask --provider local -p "…"               # providers.json names it "local"
```

```json
{ "providers": { "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:8182/v1",
                            "models": [{ "id": "llm/Ornith-1.5-9B-MLX-4bit" }] } } }
```

- **llama.cpp** needs `--jinja`, or tool calls arrive as text. A quantised KV cache (`-ctk q8_0 -ctv q8_0`) keeps a
  32k context inside 16 GiB beside a 9B model.
- **Ollama** sizes its default context from memory: 4,096 tokens here, and a longer request is refused with a 400.
  Start it with `OLLAMA_CONTEXT_LENGTH=32768`. Its library models carry the template that makes tools work.
- **MLX's** Homebrew install was broken (missing Python packages); ask's set-up uses its own `uv` environment on
  Python 3.15 instead.

## Dialects ask's decoder handles

| | llama.cpp | MLX | Ollama |
|---|---|---|---|
| reasoning field | `reasoning_content` | `reasoning` | `reasoning` |
| tool arguments | fragments | whole | whole |
| usage | final chunk | `chat.completion` object | chunk with `choices: []` |
| stray content | none | `"\n\n"` before a call | `""` in every delta |

Recordings of each are the decoder's fixtures: `Tests/Fixtures/OpenAICompatible`.

## Open

- Both suites were too easy to separate the models on quality; a harder, longer task set would.
- Not probed: LM Studio, vLLM, OpenAI's own API, hosted gateways.
