# ask

A terminal coding agent, written from scratch in Swift: reliable, fast and light.
Cold start, idle memory, input delay and action-to-action delay are budgets with
numbers, not adjectives — each is defined once in `AskCore.Budget`, printed by
`ask --budgets`, and measured by script against the release binary.

`ask -p "…"` runs one prompt through the agent loop. Without `-p`, ask opens a
full-screen terminal interface. Every run is a session file: `-c`/`--continue`
resumes the last one, `-r`/`--resume <name>` a named one, `ask sessions` lists
them all.

## Install

No binary releases yet — build from source. You need Swift 6.4 and macOS 26
(the package declares the floor and CI would test on it).

```sh
git clone https://github.com/g-cqd/ask.git
cd ask
swift build -c release
.build/release/ask login    # sign in to Claude in a browser, then:
.build/release/ask
```

`Scripts/quality.sh` runs the full gate instead — format, lint, release build
and test. It is the only entry point, so a check cannot be forgotten because
someone remembered a different command. See [Building](#building).

## The screen

Type `/` at the start of a prompt to see the commands, narrowed as you type. Up and Down choose, **Enter or Tab inserts the
choice without sending it** (a second Enter runs it), and Esc closes the list and keeps what you typed. A command typed in full runs on
Enter as before, and a path such as `/etc/hosts` is still a prompt
([ADR-0067](docs/adr/0067-the-command-picker-is-derived-from-the-draft-and-inserts-without-sending.md)). `/help` lists them too.

| Command | |
|---|---|
| `/new` | fresh conversation; the old session stays saved (stop background jobs first) |
| `/model` | show the model; `/model MODEL` or `/model PROVIDER MODEL` chooses one for this run, `/model --reset` undoes it |
| `/resume` | list sessions; `/resume NAME`, a unique prefix or a path switches without leaving the screen |
| `/config` | show the settings and re-read the files |
| `/compact` | summarise the conversation now |
| `/quit` | leave |

While the agent is working, Enter queues **steering** after its current
response and tools. `/follow-up TEXT` queues a message for when it finishes;
Alt+Enter is a shortcut on terminals that report it. Esc aborts and returns
unsent messages to the editor alongside your draft. A message is accepted only
once it is recorded in the session
([ADR-0040](docs/adr/0040-queued-input-is-acknowledged-only-after-it-is-persisted.md)).

A prompt can be several lines: paste keeps its line breaks, Shift-Enter or
Ctrl-J starts a new line, and Up/Down, Home/End, Ctrl-A/E/U/K edit the current
line.

To develop ask with ask: build it, then type `/reload`. ask checks the new
binary starts, then replaces itself with it, keeping the session
([ADR-0034](docs/adr/0034-reload-is-a-checked-re-exec-between-turns.md)).

While the agent is working, Enter queues **steering** after its current
response and tools. `/follow-up TEXT` queues a message for when it finishes;
Alt+Enter is a shortcut on terminals that report it. Esc clears a selection
first; otherwise it aborts and returns unsent messages to the editor alongside
your draft. A message is accepted only once it is recorded in the session
([ADR-0040](docs/adr/0040-queued-input-is-acknowledged-only-after-it-is-persisted.md)).

A prompt can be several lines: paste keeps its line breaks, Shift-Enter or
Ctrl-J starts a new line, and Up/Down follow wrapped display rows. Home/End
and Ctrl-A/E/U/K work on the hard line, and **Ctrl-X clears the entire
draft**. The input scrolls inside six display rows, capped at a third of the
terminal; a clipped draft shows its visible row range in the status line, and
the full draft is submitted, never just the visible slice. Set `ui.promptRows`
in `config.json` to change the requested limit, for example
`{ "ui": { "promptRows": 3 } }`.

Long output folds to one line you can open: click the line (or press Ctrl-T for thinking, Ctrl-O for tool output, Ctrl-G for code
blocks longer than 20 lines, never more than half the screen) and it opens in place. `ui.thinking`, `ui.tools` and `ui.code` choose
`"folded"` or `"open"` at the start; `ui.codeFoldLines` sets the length. A selection copies what is shown.

Background jobs are counted in the status line (`· 2 jobs`). Click the count, or type `/tasks`, to list what is running.

## Sandbox

The model's tools run inside a sandbox by default: the read, write and edit
tools check a policy, and every `bash` command runs under macOS Seatbelt with
the same one. ask's own files (`~/.config/ask`, session state) are off limits,
as are `~/.aws`, `~/.gnupg`, Keychains, `~/.netrc` and ssh private keys. A
refused command says so, and the model is told, so it does not look for a way
round. It costs about 8 ms per command
([ADR-0035](docs/adr/0035-the-sandbox-protects-ask-and-the-secret-stores-by-default.md)).

- `ask --no-sandbox` turns it off for one run.
- A `sandbox` section in your `config.json` lifts a secret store
  (`allowRead: ['~/.aws']`) or hides more (`denyRead`). A project's file may
  only hide more.
- Stricter modes: `write: 'workspace'` (or a list of paths) keeps writes in
  the project and temporary directories; `network: 'localhost'` or `'none'`
  limits the network; `read: 'workspace'` makes reading an allow-list. Any
  file may narrow these; only the `--write`, `--read` and `--network` flags
  widen them, and the status line says when the sandbox is strict
  ([ADR-0043](docs/adr/0043-strict-sandbox-modes-narrow-in-files-and-widen-only-by-flag.md)).
- SwiftPM needs `--disable-sandbox` inside ask's sandbox; ask's still applies.
- The model can narrow a single command or file operation further with a
  `sandbox` argument. If it asks for more, the screen asks you: `y` once, `a`
  for this session, `n` no ([ADR-0054](docs/adr/0054-a-tool-call-may-narrow-its-own-sandbox-and-never-widen-it.md),
  [ADR-0055](docs/adr/0055-a-widening-request-is-put-to-the-user-once-or-for-the-session.md));
  `ask -p` refuses. `narrow_sandbox` applies a narrowing to all later calls in
  the conversation; undoing it needs approval. The layer is in memory only:
  `/new`, `/resume`, restart and `/reload` drop it
  ([ADR-0057](docs/adr/0057-the-model-can-narrow-the-current-conversation-and-only-the-user-can-undo-it.md)).

## Configuration

Settings live in `config.json` — JSON or JSON5 (comments, unquoted keys,
trailing commas) — in `~/.config/ask/` and in a project's `.ask/`. The keys
are `model`, `provider`, `thinking`, `maxTurns`, `compactAt` and `ui`. Layers apply
lowest first: built-in defaults, the user file, the project file, `ASK_*`
environment variables, flags. `ask config` shows each value and where it came
from.

`thinking` (`--thinking`, `ASK_THINKING`) asks for `off`, `minimal`, `low`,
`medium`, `high`, `xhigh` or `max`. ask sends only what the model's own list
says it accepts (`ask models anthropic` shows each Claude model's modes and
efforts), refuses a level the model lacks instead of picking another, and says
when a server could still refuse a level it cannot check
([ADR-0060](docs/adr/0060-thinking-is-a-request-the-model-s-own-metadata-must-allow.md)).
Chat-completions servers have no verified field, so an explicit level is
refused there.

A project's file is text from a repository, so it is ignored until you run
`ask trust` in that project, at a terminal, and ignored again if it changes.
Edits are picked up at the next prompt; a broken edit is reported and the
previous settings stay
([ADR-0032](docs/adr/0032-configuration-is-json-or-json5-in-layers-and-a-project-file-needs-trust.md)).

## Providers

Claude is built in: `ask login`, or an environment variable —
`ANTHROPIC_AUTH_TOKEN` (bearer token for a gateway), `ANTHROPIC_OAUTH_TOKEN`,
then `ANTHROPIC_API_KEY`; the first one set is used, and one that is not a
plain token stops the run.

Any server that speaks OpenAI chat completions (llama.cpp, MLX, Ollama, LM
Studio, vLLM, hosted gateways) is configuration, in
`~/.config/ask/providers.json`, in the shape pi's `models.json` uses:

```json
{ "default": "local",
  "providers": { "local": { "api": "openai-completions", "baseUrl": "http://127.0.0.1:8182/v1",
                            "apiKey": "$LOCAL_KEY", "models": [{ "id": "my-model" }] } } }
```

- `ask --provider NAME --model ID` overrides both. A key is read from `$NAME`
  and never sent over plain `http` to another machine
  ([ADR-0024](docs/adr/0024-a-credential-is-never-sent-in-the-clear-to-another-machine.md),
  [ADR-0027](docs/adr/0027-openai-compatible-providers-by-configuration.md)).
- Twenty-four services are known by name and need only their key variable
  (`--provider groq` with `GROQ_API_KEY`), as in pi.
- `ask login NAME` signs in by browser and stores the key it is issued:
  `spettro`, `mistral-vibe`, and `codex` (a ChatGPT subscription; `--device`
  for a code typed at a link). `ask --provider codex` uses the first model your
  account lists (`ask models codex` shows them; `--model ID` chooses).
  `api: "openai-responses"` points an entry at any server speaking the
  Responses API.
- Two accounts of one provider can be signed in at once as named connections:
  `ask login codex --name work`, then `--provider work`; `ask connections`
  (with `rename` and `remove`) manages them. Each has its own credentials and
  model list; a session remembers which connection it used and resumes on it,
  and ask never moves a prompt to another account on its own
  ([ADR-0048](docs/adr/0048-named-connections-are-registered-destinations-with-stable-identities.md)).
- `ask models NAME` also refreshes an OpenAI-compatible provider's model list
  and reported limits (cached for up to a day; limits stated in
  `providers.json` win). `ask logout [NAME]` forgets one sign-in, or all.

What is verified and what is not: browser sign-in, inference and a read/write
tool loop are verified with a real ChatGPT account
([live results](docs/diary/2026-10-20-27.md)); direct OpenAI-account use
remains unverified, and model availability depends on your account.
Authenticated model lists on other presets remain unverified. Key-based caches
are endpoint-scoped, not account-scoped: refresh after changing keys or routing
headers. For Ollama, start it with `OLLAMA_CONTEXT_LENGTH=32768`: its default
context is sized from memory and can be 4,096 tokens. Measured local set-ups:
[docs/research/local-models-2026-10.md](docs/research/local-models-2026-10.md).

## Extensions

An extension is an executable, in any language, that adds tools to ask and
sees tool calls before and after they run; ask starts it as a child process and
talks over stdio. The protocol is a versioned draft:
[docs/protocol/extensions.md](docs/protocol/extensions.md)
([ADR-0028](docs/adr/0028-extensions-are-processes-hooks-are-in-the-loop.md);
the host is roadmap 0033).

## Status

Five libraries and the `ask` composition root, green in release:
`AskCore` (budgets, documentation layout, source standards), `AskAI`
(provider-neutral `Model` and `Transport`, with `Anthropic` and `Claude` as the
one provider so far), `AskAgentCore` (the agent loop, tools contract,
sessions), `AskTools` (`read`, `write`, `edit`, `bash`, and jobs: `wait`,
`job_input`, `job_stop`), `AskTUI` (the interactive screen). Not built yet: a
second provider, the codemode host.

Every exit path of the terminal loop writes the reset ladder, and a shutdown
signal both restores the terminal and dies with `128 + signo` (verified on a
PTY: 143 for `SIGTERM`, 130 for `SIGINT`).

The standards are enforced rather than requested, as tests that run inside
`swift test`: banned constructs and unjustified `@unchecked Sendable`
(`SourceStandards`), one type per file and a 250-line ceiling
(`SourceStructureTests`, [ADR-0021](docs/adr/0021-structure-is-a-gate-not-a-habit.md)),
provider names only in provider code, and the shape of the ADRs and the
roadmap. `Scripts/analyzers.sh` adds unused code, duplicated code and retain
cycles ([ADR-0022](docs/adr/0022-static-analyzers-are-gates-pinned-by-version-and-hash.md)).
Each rule was probed by breaking it.

Measured against the budgets: idle memory about 9 MiB of its 24 MiB budget
([ADR-0038](docs/adr/0038-the-idle-memory-budget-is-24-mib.md)), and the
action — a tool call to its result on screen — about 2.6 ms of 5 ms
([ADR-0053](docs/adr/0053-the-action-budget-is-a-tool-call-to-its-result-on-screen.md)).
`Scripts/measure-budgets.py` reproduces both against the release binary on a
PTY.

## The evidence rule

Read [docs/WHITE-PAPER.md](docs/WHITE-PAPER.md) first — it carries the
principles. Every claim is named, given a probe that could fail, run, and
recorded in the diary before it is acted on; a probe that cannot fail is not a
probe, and unprobed claims are written as open questions, never as facts. The
diary ([docs/diary/](docs/diary/)) is where probe history lives, and where
refuted beliefs are recorded — they are the most valuable lines in the
repository.

## Layout

| Path | What |
|---|---|
| `docs/WHITE-PAPER.md` | the rules this project runs on, and the probe ledger |
| `docs/adr/` | one decision per file; superseded by new records, never rewritten |
| `docs/roadmap/` | one entry per file — a unit of work, claimable on its own |
| `docs/diary/` | the working log, capped at 256 lines per file |
| `docs/protocol/` | the extension protocol |
| `docs/research/` | notes from studying other systems |

## Roadmap

`docs/roadmap/` is the plan, one claimable unit of work per file; read an
entry's `status:` and `blocked-by:` before starting it. `Scripts/roadmap.sh
open` prints the open entries from their front matter.

## Building

```sh
Scripts/quality.sh            # format, lint, build and test
Scripts/quality.sh --check    # verify only; what CI would run
```

Release only, always — see
[ADR-0002](docs/adr/0002-release-only-no-testable.md). A debug build measures
a program nobody ships. Style and size are Aemi's canonical configuration,
synced rather than reinvented: swift-format owns style, SwiftLint owns size
and complexity.

**CI has never run**: GitHub refuses to start the jobs for a billing reason,
so the gates are enforced by `Scripts/quality.sh` and the git hooks, not by
CI — a pull request gets no machine feedback, so run the script locally
([CONTRIBUTING.md](CONTRIBUTING.md)).

## Foundation

The kernel tier and the deterministic test kit come from
[Aemi](https://github.com/Aemi-Studio/aemi) (pinned by revision; it publishes
no tags), the JSON stack from
[AemiJSON](https://github.com/g-cqd/AemiJSON)
([ADR-0015](docs/adr/0015-aemijson-and-argument-parser.md)), session-file
durability from AemiIO
([ADR-0017](docs/adr/0017-session-files-are-append-only-and-barrier-flushed.md)),
and child processes from
[swift-subprocess](https://github.com/swiftlang/swift-subprocess) behind an
injected interface
([ADR-0011](docs/adr/0011-official-subprocess-for-tools.md)). The terminal
stack comes from [TerminalKit](https://github.com/g-cqd/TerminalKit), pinned
by full revision
([ADR-0005](docs/adr/0005-ask-depends-on-terminalkit.md)).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: run
`Scripts/quality.sh --check` before you push, commit messages state *why*
(the diff already says what), and a claim arrives with a probe that could fail
or is marked as an open question.

## License

[MIT](LICENSE).
