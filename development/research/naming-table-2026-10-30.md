# Names and wording: as they are, as proposed (roadmap 0154, with 0118 and 0096)

For the owner to answer row by row: "yes", "no", or another name. Nothing is renamed before that. Every rename keeps the old name
readable for a release, with a notice naming the new one; `ask config`, the configuration page and the generated example change together.
Inventory taken 2026-10-30 from `docs/configuration.md`, `ask --help`, every subcommand's help, `SlashCommand` and the messages.

## Conventions the rows apply

- **C1. Switches are JSON booleans.** `true`/`false`, as `ui.mouse` and `ui.copyOnSelect` are already stored by `/config`; `"on"`/`"off"`
  stay accepted (they already are). Twelve settings are documented as `"on"`/`"off"` today (eleven in `ui`, and `skills.enabled`), while
  `mcp.*.enabled` is documented as `false` and `/config` writes `ui.mouse` and `ui.copyOnSelect` as booleans.
- **C2. A key names what you see, not the mechanism**, and a switch reads as a yes/no question about it (`ui.tint: true`).
- **C3. One word per idea, everywhere:** *input* is the field you type in, *prompt* what you send; *stop* is what you do to a turn, and
  *interrupted* what it shows afterwards; *job* is a command running in the background; *allow* means "run without asking" and
  nothing else (the sandbox's exceptions get another word); *connection* is a configured account of a provider.
- **C4. A flag mirrors its setting:** `--network` ↔ `sandbox.network`, `--allow` ↔ `approvals.allow`; a list flag is repeatable.
- **C5. Command arguments are bare words** (`/logout all`), not `--options` (`/model --reset`).

## Settings

| # | As it is | Proposed | Why |
|--:|---|---|---|
| 1 | eleven `ui.*` switches and `skills.enabled` as `"on"`/`"off"` | booleans (C1) | one spelling; JSON's own; what `/config` writes for two of them already |
| 2 | `ui.promptRows` | `ui.inputRows` | C3: it is the input's height |
| 3 | `ui.prompt` (text the input starts with) | `ui.inputPrefix` | C3; "prompt" is what you send |
| 4 | `ui.tools`, `ui.thinking`, `ui.code`: `"folded"`/`"open"`; `ui.codeFoldLines` | `ui.fold.tools`, `ui.fold.thinking`, `ui.fold.code`: booleans; `ui.fold.codeLines` | `ui.thinking` beside the top-level `thinking` (a level) reads as the same setting; the four belong together |
| 5 | `ui.localizedDurations` | `ui.durations: "words"` or `"clock"` | C2: says what you see (`1 hr, 40 min` against `1:40:00`) |
| 6 | `ui.timeout: "auto"/"always"/"never"` | `ui.showTimeout`, same values | `ui.timeout` reads as a duration, as if it set the commands' time limit |
| 7 | `ui.timeoutLabel` | unchanged | follows row 6 |
| 8 | `ui.interruptKeys: "esc"/"ctrl-c"/"both"` | `ui.stopKeys`, same values | C3 |
| 9 | `ui.escapeInterruptRequiresConfirmation` (`"on"`), `ui.abortTurnRequiresConfirmation` (`"off"`) | `ui.stopTwice: ["esc"]`: the keys that must be pressed twice | two long names for one idea; "abort" and "interrupt" are both "stop" |
| 10 | `ui.interruptSendsQueued: "all"/"next"/"none"` | `ui.queuedOnStop`, same values | C3 |
| 11 | `ui.jobAutoReturnWhenFocused` | `ui.leaveFinishedJob` (boolean) | C2: what happens, said shortly |
| 12 | `ui.onlyUsefulModels` (`"on"`) | `ui.listAllModels` (`false`) | mirrors `ask models --all` (C4); "useful" is a judgement |
| 13 | `ui.sidebar: "closed"/"open"` | unchanged | a panel opens and closes; a block folds |
| 14 | `ui.mouse`, `ui.copyOnSelect`, `ui.tint`, `ui.separator`, `ui.padding`, `ui.markdown`, `ui.appearance`, `ui.spinner`, `ui.scrollLines` | unchanged (booleans per row 1) | already short and about what you see |
| 15 | `keepAwake: "system"/"display"/"always"/"off"` | `keepAwake: "working"/"always"/"off"` and `keepDisplayAwake` (boolean) | two questions in one list: *when* (working, always) and *what* (the Mac, the display); today "always" with the display cannot be said |
| 16 | `sandbox.denyRead` | `sandbox.hide` | the docs already say "more paths to hide" |
| 17 | `sandbox.allowRead`, `sandbox.allowWrite` | `sandbox.readable`, `sandbox.writable` | C3: "allow" belongs to approvals; these lift a protection |
| 18 | `sandbox.write`, `sandbox.read`, `sandbox.network` | unchanged | mirrored by `--write`, `--read`, `--network` |
| 19 | `approvals.scope: "anything"/"narrowing-only"/"none"` | `approvals.remember: "anything"/"narrowing"/"none"` | says what it governs: what an "always" answer may write back |
| 20 | `approvals.default`, `approvals.allow`, `approvals.ask` | unchanged; `ask` also takes `"commands"` and `"all"` | symmetry with `allow` (0156), which row 23 needs |
| 21 | `skills.maxAdvertised` | `skills.maxListed` | plainer word for the same thing |
| 22 | `model`, `provider`, `thinking`, `maxTurns`, `compactAt`, `credentials`, `skills.sources`, `mcp` (and its fields), `environment.*` | unchanged | consistent already; `provider` stays the key though the value is a connection (row 31) |

## Flags

| # | As it is | Proposed | Why |
|--:|---|---|---|
| 23 | `--ask-always` | `--ask NAME`, repeatable, mirroring `--allow` (C4); `--ask all` is today's `--ask-always` | one pair of verbs for one idea; `--ask commands` becomes possible |
| 24 | `--yes` | unchanged, documented as `--allow all` | short and common in other tools |
| 25 | `--no-sandbox`, `--network`, `--write`, `--read`, `--model`, `--provider`, `--thinking`, `--max-turns`, `--compact-at`, `-p`, `-c`, `-r`, `-v` | unchanged | each mirrors its setting or is a habit other agents share |
| 26 | `--yes`'s help says "(roadmap 0134)" | drop the roadmap number | help is for people running ask |
| 27 | `ASK_MODEL`, `ASK_PROVIDER`, `ASK_THINKING`, `ASK_MAX_TURNS`, `ASK_COMPACT_AT` | unchanged | mirror the keys |

## Commands

| # | As it is | Proposed | Why |
|--:|---|---|---|
| 28 | `/tasks` ("background jobs") | `/jobs`, `/tasks` kept as another name | C3: everything else says job |
| 29 | `/config now` (show every setting and its source) | `/config show` | "now" means "without waiting" in `/reload now` |
| 30 | `/model … --reset` | `/model reset` | C5 |
| 31 | `ask connections`, "provider" in `--provider`'s help and in prose | "connection" in prose and help for a configured account; "provider" for the company or protocol | 0046 settled the model; the words lag behind |
| 32 | `/tree` (go back to before a prompt) | `/rewind`, `/tree` kept | says what it does; "tree" names a structure you never see |
| 33 | `/follow-up TEXT` | unchanged | — |
| 34 | `/help`'s line "Ctrl+C: erase, stop, quit (twice). Ctrl+T/O/G fold. Enter steers." | unchanged words, keys from `ui.stopKeys` | follows row 8 |
| 35 | `/compact`, `/new`, `/resume`, `/fork`, `/thinking`, `/login`, `/logout`, `/mcp`, `/reload`, `/sidebar`, `/verbose`, `/continue`, `/quit`, `/skill:NAME` | unchanged | short, and what other agents call them |

## Messages

| # | As it is | Proposed | Why |
|--:|---|---|---|
| 36 | "The user did not allow this call." and "The user did not allow X on the MCP server…" (read by the model) | unchanged: "the user" in what the model reads, "you" in what a person reads (as the docs do) | the model's own vocabulary; listed so new messages follow the same split |
| 37 | "Not permitted: PATH." (sandbox), "This call was blocked before it ran", "… was refused" | sandbox: "Not permitted"; hooks: "Blocked"; providers and servers: "refused" | three different causes keep three words, used only for their cause; listed so new messages follow it |
| 38 | answers "Allow this time", "Allow for the session", "Allow the program for the session", "Deny" | unchanged | approved in 0116 |
| 39 | `⊘` and the orange "interrupted" mark; "Sign-in stopped." | unchanged | *stop* is the act, *interrupted* the state (C3) |
| 40 | the search-mode MCP tools `search_catalog`, `dispatch_call` (renamed from `mcp_search`, `mcp_call`, which Anthropic refuses on a subscription, 0144) | unchanged until another pair is checked live | the only names known to pass |

## After the answers

One `SettingDescriptor` list in `AskAgentCore` (key, old names, type, default, choices, which layers may set it, one line of help) that
the parser, the `/config` editor (which today lists no `approvals` row), `ask config`, `docs/configuration.md`'s tables and a generated
`config.example.json5` all read; a test fails when one of them names a key the list does not.
