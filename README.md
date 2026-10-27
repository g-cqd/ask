# ask

A terminal coding agent, written from scratch in Swift: reliable, fast and light.
Cold start, idle memory, input delay and action-to-action delay are budgets with
numbers, not adjectives — each is defined once in `AskCore.Budget`, printed by
`ask --budgets`, and measured by script against the release binary.

`ask -p "…"` runs one prompt through the agent loop. Without `-p`, ask opens a
full-screen terminal interface. Every run is a session file: `-c`/`--continue`
resumes the last one, bare `-r`/`--resume` opens a searchable session picker,
and `--resume <name>` resumes directly. `ask sessions` lists them all.

## Install

No binary releases yet — build from source. You need Swift 6.4 and macOS 26
(the package declares the floor and CI would test on it).

```sh
git clone https://github.com/g-cqd/ask.git
cd ask
swift build -c release
.build/release/ask login    # sign in to Claude in a browser, then:
.build/release/ask          # or just `ask`: with nothing signed in it uses Apple's on-device model, and /login signs in
```

`Scripts/quality.sh` runs the full gate instead — format, lint, release build
and test. It is the only entry point, so a check cannot be forgotten because
someone remembered a different command. See [Building](#building).

## The screen

Type `/` at the start of a prompt to see the commands, narrowed as you type. Up and Down choose, **Enter or Tab inserts the
choice without sending it** (a second Enter runs it), and Esc closes the list and keeps what you typed. A click on a row does what Enter does
([ADR-0070](docs/adr/0070-a-click-on-a-picker-row-is-the-choice-and-enter-in-one-gesture.md)). A command typed in full runs on
Enter as before, and a path such as `/etc/hosts` is still a prompt
([ADR-0067](docs/adr/0067-the-command-picker-is-derived-from-the-draft-and-inserts-without-sending.md)). `/help` lists them too.

Type `@` at the start of a word to point at a file: the project's files are listed (git's own list, so `.gitignore` applies, and only
what the sandbox lets ask read), narrowed as you type, with the same keys. **Enter or Tab inserts `@path`** and nothing is sent or
attached; add `:12-30` for a line range. The model reads the file itself, under the sandbox
([ADR-0069](docs/adr/0069-the-file-picker-inserts-a-path-and-lists-only-what-ask-may-read.md)).

| Command | |
|---|---|
| `/new` | fresh conversation; the old session stays saved (stop background jobs first) |
| `/model` | type `/model ` for a list of every model of every account you are signed in to (and Apple's on-device model); Up and Down, Enter or a click chooses it at once, and the effort list for it opens next. `/model MODEL`, `/model PROVIDER/MODEL` or `/model PROVIDER MODEL` also work (an unqualified model goes to the account whose list holds it, [ADR-0118](docs/adr/0118-the-provider-follows-the-model-and-the-effort.md)), `/model --reset` undoes it ([ADR-0117](docs/adr/0117-accounts-models-and-effort-are-chosen-inside-the-conversation.md)) |
| `/thinking` | type `/thinking ` for the efforts the current model takes; `/thinking LEVEL` sets one for this run |
| `/login` | type `/login ` to sign in to a provider without leaving: Claude, Codex, Antigravity, Spettro, Mistral Vibe by account, or any of them (and any key preset, and `custom NAME URL` for an OpenAI-compatible server) with an API key. A key is typed hidden and kept out of the transcript |
| `/logout` | type `/logout ` to sign out of one account, or `/logout all`, without leaving |
| `/resume` | searchable session picker; `/resume NAME`, a unique prefix or a path switches directly without leaving the screen |
| `/tree` | list this session's prompts; `/tree N` goes back to before prompt N and puts it in the editor, so the next message branches from there ([ADR-0093](docs/adr/0093-a-session-is-navigated-by-going-back-to-before-one-of-its-prompts.md)) |
| `/fork` | continue in a new session; `/fork N` does so from before prompt N. The original stays saved and untouched ([ADR-0094](docs/adr/0094-a-fork-continues-a-session-in-a-file-of-its-own-and-leaves-the-original-alone.md)) |
| `/config` | show the settings and re-read the files |
| `/compact` | summarise the conversation now |
| `/quit` | leave |

Scroll back with the wheel or Page Up and the screen stays on what you were reading while more text arrives below it; the status
line says how many lines are below (`12 lines below`). Click that count, press End with an empty draft, or press Page Down to return to
the end ([ADR-0072](docs/adr/0072-the-view-holds-while-text-arrives-below-and-the-status-line-counts-it.md)).

While the agent is working, Enter queues **steering** after its current
response and tools. `/follow-up TEXT` queues a message for when it finishes;
Alt+Enter is a shortcut on terminals that report it. Ctrl+C with an empty
input stops the turn and returns unsent messages to the editor. A message is accepted only
once it is recorded in the session
([ADR-0040](docs/adr/0040-queued-input-is-acknowledged-only-after-it-is-persisted.md)).

**Keys** ([ADR-0104](docs/adr/0104-escape-only-goes-back-and-control-c-is-a-ladder-that-never-quits-on-the-first-press.md)):
Esc only goes back: it clears a selection and closes a list, and never stops a turn, quits, or clears what you typed. Ctrl+C is one step a press: it copies a
selection; otherwise erases the draft; otherwise, with a turn running, stops it; otherwise the status line says `press Ctrl+C again to quit`, and a second
press within two seconds quits (any other key cancels it). So with text typed during a turn, press Ctrl+C twice to erase it and stop. Ctrl+D on an empty,
idle input still quits, and `/quit` always does.

A prompt can be several lines: paste keeps its line breaks, Shift-Enter or
Ctrl-J starts a new line, and Up/Down, Home/End, Ctrl-A/E/U/K edit the current
line.

To develop ask with ask: build it, then type `/reload`. ask checks the new
binary starts, then replaces itself with it, keeping the session
([ADR-0034](docs/adr/0034-reload-is-a-checked-re-exec-between-turns.md)).

While the agent is working, Enter queues **steering** after its current
response and tools. `/follow-up TEXT` queues a message for when it finishes;
Alt+Enter is a shortcut on terminals that report it. Ctrl+C with an empty
input stops the turn and returns unsent messages to the editor. A message is accepted only once it is recorded in the session
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
`"folded"` or `"open"` at the start; `ui.codeFoldLines` sets the length. Elapsed status is hidden on model answers and for operations lasting one second or less.
Longer tool and thinking blocks use localized units (for example, `1 hr, 40 min, 30 sec`);
set `"ui": {"localizedDurations": "off"}` in configuration for a compact clock instead
(`1:40:30`, `1:01`, or `2` seconds). Zero-valued units are omitted in localized mode.
Background jobs continue streaming into their original foldable tool block, even while
another job is focused. They use short `[#7a2f]` display identities; `wait`, `job_input`
and `job_stop` also accept `#7a2f` or `7a2f` (legacy `job-N` references still work).
A completed job adds one faint italic outcome row with trailing elapsed/count/status.

The jobs list sits one blank row below status. Each active job shows its elapsed time
and a single-cell spinner at the right edge; these keep updating while the model is idle.

Set `"ui": {"jobAutoReturnWhenFocused": "off"}` to keep a finished job's focused output
visible until Escape (default: `"on"`, return to main). Set
`"ui": {"abortTurnRequiresConfirmation": "on"}` to require two consecutive Ctrl+C presses
within two seconds to abort a turn (default: `"off"`). Ctrl+C still clears a draft first;
Escape only navigates and never aborts a turn.

Animated spinners accompany ongoing operations and lead the status line; set
`"ui": {"spinner": "braille"}` (or `braillefull`, `braillequarter`, `snake`, `line`, `dot`, `star`, `random`)
to customize the animation style. Each spinner frame strictly occupies 1 column. In the status line,
running operations show the spinner in bold white when sandboxed or yellow when unsandboxed; idle sessions
display `!` in yellow when unsandboxed or omit the indicator when sandboxed. Ongoing jobs are displayed at
the end of the status line.

A selection copies what is shown.

A click in the input puts the cursor there; a drag there selects text, a double click takes a word and a triple click a line; Shift with an arrow, Home or End selects from the keyboard; typing replaces a selection, Backspace deletes it and Ctrl-C copies it and Ctrl-X cuts it (with nothing selected, Ctrl-X clears the draft). The wheel over a long draft scrolls it.

Skills (a directory with a `SKILL.md`, from any harness's skills directory) are listed to the model, which loads one with the `skill` tool when a task matches;
`ask skills` shows what was found and `skills` in `config.json` sets `enabled`, `maxAdvertised` (default 32) and `sources`. A skill grants nothing, and a
project's skills load only after `ask trust --skills`, in a terminal, has trusted each file as it is. `/skill:name request` asks for one yourself, and the `/` picker lists them.

MCP servers (a program ask starts, or a URL) are named under `mcp` in your own `config.json` and their tools are offered to the model as
`mcp__<server>__<tool>`; `/mcp` shows which are connected. A server runs outside ask's sandbox, so naming one is the consent: a project's
file can name one only once you have trusted it (`ask trust` lists what would start), and a server with more than 16 tools is searched (`mcp_search`, `mcp_call`) instead of listed unless `tools` names the ones you want. See ADR-0099, ADR-0100 and ADR-0103. A tool the server marks destructive is asked about first, once a tool a session (ADR-0111).

Background jobs are counted in the status line (`· 2 jobs`). Click the count, or type `/tasks`, to open a capped runner strip **below the input**, showing each
job's command and state. Down from an empty draft (or the end of one) moves into the strip; Up and Down choose a job, Enter or a click shows what it has printed in place of the conversation
(a snapshot, read when you focus it), and Esc goes back one step at a time: to the input, then to the conversation, then it closes the strip. It never clears your draft. On a screen of 70 columns or more, `/sidebar` or Ctrl+\\ shows the same tree in a column beside the transcript (`ui.sidebar` set to `"open"` starts it open), with the same keys and clicks. A job does not outlive ask, even when ask is killed with SIGKILL: a small watchdog process stops it
([ADR-0079](docs/adr/0079-a-watchdog-outside-ask-stops-the-jobs-when-ask-is-killed.md)).

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
include `model`, `provider`, `thinking`, `maxTurns`, `compactAt`, `ui` and `environment`. Layers apply
lowest first: built-in defaults, the user file, the project file, `ASK_*`
environment variables, flags. `ask config` shows each value and where it came
from.

Commands inherit your environment except ask's known credential variables, `ANTHROPIC_*`, `ASK_*`, and variables referenced by provider keys or MCP headers/environment.
In your user file, `environment: { pass: ['OPENAI_API_KEY'], withhold: ['MY_SERVICE_TOKEN', 'AWS_*'] }` explicitly passes a withheld key or withholds additional names.
Withholding wins; projects may only add withholding. `/config` shows policy, never values. Unknown secrets remain inherited unless you withhold them.
ask also blanks those variables in its own process once it has read them, so a command cannot recover them from there either ([ADR-0113](docs/adr/0110-ask-blanks-the-credentials-it-has-read-from-its-own-environment.md)). A secret ask does not know about is still inherited unless you withhold it.

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

Nothing needs configuring to start. With no flag, no configuration and no `providers.json` default, ask uses the first account that can answer: Claude, then
Codex, then Antigravity, and when none is signed in Apple's on-device model (`apple`, one model, `on-device`, run in this process: no account, no key, no cost; its
window is small, so it is for questions and short edits —
[ADR-0116](docs/adr/0116-apple-intelligence-is-linked-not-launched.md)). `/login` signs in without leaving the screen, with an account or an API key.

Claude is built in: `ask login`, `ask login claude --api-key`, or an environment variable —
`ANTHROPIC_AUTH_TOKEN` (bearer token for a gateway), `ANTHROPIC_OAUTH_TOKEN`,
then `ANTHROPIC_API_KEY`; the first one set is used, and one that is not a
plain token stops the run. `ask login codex --api-key` stores an OpenAI API key (provider `openai`);
`ask login custom NAME URL` adds any OpenAI-compatible server to `providers.json` and stores its key apart from it.

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

Six libraries and the `ask` composition root, green in release: `AskCore` (budgets, documentation layout, source standards), `AskAI`
(provider-neutral `Model` and `Transport`; Claude, Codex, Antigravity, and OpenAI-compatible or Responses servers by configuration or
preset), `AskAgentCore` (the agent loop, tools contract, sessions, compaction), `AskTools` (`read`, `write`, `edit`, `bash`, and jobs:
`wait`, `job_input`, `job_stop`), `AskMCP` (an MCP client) and `AskTUI` (the interactive screen). Not built yet: the codemode host, the
extension host, subagents, and a versioned release. What is not yet known is written down in `docs/research/`.

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
