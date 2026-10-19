# ask

A Swift coding agent.

`ask` is a terminal coding agent written from scratch in Swift, built to be reliable, fast and light:
cold start, idle memory, input delay, and action-to-action delay are budgets with numbers, not
adjectives.

## Read this first

**[docs/WHITE-PAPER.md](docs/WHITE-PAPER.md)** — the project rules. Paste it at the start of any
iteration. It leads with the evidence rule: every claim is challenged and backed by an actual probe
before it is adopted, and there is no place for an assumption.

## Layout

| Path | What |
|---|---|
| `docs/WHITE-PAPER.md` | The rules this project runs on, and the probe ledger |
| `docs/adr/` | One decision per file |
| `docs/roadmap/` | One entry per file — a unit of work, claimable on its own |
| `docs/diary/` | The working log, capped at 256 lines per file |

## Status

Six library targets and the `ask` executable, green in release (`Scripts/quality.sh`): `AskCore` (budgets),
`AskAI` (provider-neutral `Model` and `Transport`, with `Anthropic` and `Claude` as the one provider so far),
`AskAgentCore` (the agent loop, tools contract, sessions), `AskTools` (`read`, `write`, `edit`, `bash`),
`AskTUI` (the interactive screen) and the `ask` composition root. `ask -p` runs one prompt through the loop, on Claude or any OpenAI-compatible server;
without `-p` it opens the full-screen interface. Every run is a session file: `-c`/`--continue` resumes the
last one, `-r`/`--resume <name>` a named one, and `ask sessions` lists them. Not built: a second provider, the codemode host, sandboxing.

Every exit path of the terminal loop writes the reset ladder, and a shutdown signal both restores the
terminal and dies with `128 + signo` (verified on a PTY: 143 for `SIGTERM`, 130 for `SIGINT`).

The standards are enforced rather than requested, as tests that run inside `swift test`: banned constructs
and unjustified `@unchecked Sendable` (`SourceStandards`), one type per file and a 250-line ceiling
(`SourceStructureTests`, ADR-0021), provider names only in provider code, and the shape of the ADRs and the
roadmap. `Scripts/analyzers.sh` adds unused code, duplicated code and retain cycles (ADR-0022). Each rule was
probed by breaking it.

**The four budgets are measured**, by `Scripts/measure-budgets.py` against the release binary on a PTY.
Idle memory is currently **over** its budget, and the action-to-action figure is provisional
([roadmap 0007](docs/roadmap/0007-re-derive-the-action-budget.md)). **CI has never run**: GitHub refuses to start
the jobs for a billing reason, so the gates are enforced by `Scripts/quality.sh` and the git hooks, not by CI.

## Providers

Claude is built in (`ask login`, or `ANTHROPIC_API_KEY`). Any server that speaks OpenAI chat completions (llama.cpp,
MLX, Ollama, LM Studio, vLLM, hosted gateways) is configuration, in `~/.config/ask/providers.json`, in the shape pi's
`models.json` uses:

```json
{ "default": "local",
  "providers": { "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:8182/v1",
                            "apiKey": "$LOCAL_KEY", "models": [{ "id": "my-model" }] } } }
```

`ask --provider NAME --model ID` overrides both. A key is read from `$NAME`, never sent over plain `http` to another
machine (ADR-0024, ADR-0027). For Ollama, start it with `OLLAMA_CONTEXT_LENGTH=32768`: its default context is sized
from memory and can be 4,096 tokens. Measured local set-ups: `docs/research/local-models-2026-10.md`.

## Roadmap

`docs/roadmap/` is the plan, one claimable unit of work per file; read an entry's `status:` and `blocked-by:`
before starting it. `Scripts/roadmap.sh open` prints the open entries from their front matter.

## Building

```sh
Scripts/quality.sh            # format, lint, build and test
Scripts/quality.sh --check    # verify only; what CI would run
```

Release only, always — see [ADR-0002](docs/adr/0002-release-only-no-testable.md). A debug build
measures a program nobody ships.

Style and size are Aemi's canonical configuration, synced rather than reinvented: swift-format owns
style, SwiftLint owns size and complexity.

## Foundation

The kernel tier and the deterministic test kit come from [Aemi](https://github.com/Aemi-Studio/aemi).
The terminal stack comes from **TerminalKit**, its own repository — see
[ADR-0005](docs/adr/0005-ask-depends-on-terminalkit.md).

Aemi publishes no tags, so `ask` depends on it by pinned revision, as Atelier already does. TerminalKit
has no GitHub remote yet, which blocks a shipping dependency on it.