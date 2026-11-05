# Configuration

ask works without any configuration. When you want to change something, put it in a `config.json`:

- `~/.config/ask/config.json` for you, everywhere (or `$XDG_CONFIG_HOME/ask/config.json`);
- `.ask/config.json` in a project, for that project only.

The file is JSON, or JSON5 if you like comments, unquoted keys and trailing commas. Set only what you want to change; everything else keeps
its default. To see what is in force and where each value came from, run:

```sh
ask config
```

Inside ask, `/config` opens an editor for the same settings, and `/config show` re-reads the files and shows them. ask watches the files while it
runs: a saved change applies at once, to a running turn from its next request, and your draft is left as it is (`/verbose` lists
what changed). A project file is noticed even when its `.ask` folder did not exist when ask started. If an edit is broken, ask
says so and keeps the previous settings.

## Common recipes

Use a particular model by default:

```json5
{ model: "claude-sonnet-5-5" }
```

Think harder by default (the model must support the level; see [Providers and accounts](providers.md#thinking)):

```json5
{ thinking: "high" }
```

Keep tool output and thinking open instead of folded:

```json5
{ ui: { fold: { tools: false, thinking: false } } }
```

A plainer screen, with no tinted blocks, padding or separator:

```json5
{ ui: { tint: false, padding: false, separator: false } }
```

Let the terminal handle the mouse (its own selection and scrolling):

```json5
{ ui: { mouse: false } }
```

Make one Esc enough to stop a running turn, or keep Esc out of it entirely:

```json5
{ ui: { stopTwice: [] } }                               // one Esc stops the turn
{ ui: { stopKeys: "ctrl-c" } }                          // only Ctrl+C stops it
```

Compact the conversation earlier, at half of the model's context window:

```json5
{ compactAt: 0.5 }
```

Keep commands from writing outside the project, and off the network:

```json5
{ sandbox: { write: "workspace", network: "none" } }
```

Let commands read `~/.aws` (hidden by default), in your own file:

```json5
{ sandbox: { readable: ["~/.aws"] } }
```

Run commands with fish instead of bash:

```json5
{ environment: { shell: "fish" } }
```

## Where a value comes from

Layers apply in this order, each one overriding the one before:

1. ask's defaults;
2. your file, `~/.config/ask/config.json`;
3. the project's file, `.ask/config.json`;
4. environment variables: `ASK_MODEL`, `ASK_PROVIDER`, `ASK_THINKING`, `ASK_MAX_TURNS`, `ASK_COMPACT_AT`;
5. command-line flags: `--model`, `--provider`, `--thinking`, `--max-turns`, `--compact-at`, `--network`, `--write`, `--read`,
   `--no-sandbox`, `--yes`, `--yolo`, `--allow`, `--ask`.

Inside a section such as `ui`, a layer replaces only the keys it sets. A later file adds to an earlier one and never wipes it:

- a list that protects adds up: `sandbox.hide` and `environment.withhold` keep every layer's entries;
- `sandbox.write`, `sandbox.read` and `sandbox.network` only narrow: you get what every layer allows;
- `mcp` goes by server name: a server the project defines in full replaces yours of that name, and an entry with no `command` or
  `url` changes one of yours (see [`mcp`](#mcp)); servers it does not name are kept;
- the settings marked "Your own file only" come from your file alone, so a project can neither add to nor replace them.

**A project's file is ignored until you trust it.** It comes from a repository, so it could have been written by anyone. Run `ask trust` in
the project, at a terminal, to trust it as it is now; if it changes, it is ignored again until you trust it again. `ask untrust` stops
trusting it. Some settings can only come from your own file, as the tables below say.

`docs/config.example.jsonc` holds every setting below with an example value and its default, generated from the code so it never
drifts; copy from it only what you want to change.

## Older names

Some settings were renamed on 2026-10-30. A file that uses an old name still loads, as the new name, and ask says so once at the start;
`/config` writes the new names when it saves.

| Old | New |
|---|---|
| `ui.promptRows`, `ui.prompt` | `ui.inputRows`, `ui.inputPrefix` |
| `ui.tools`, `ui.thinking`, `ui.code` (`"folded"`/`"open"`), `ui.codeFoldLines` | `ui.fold.tools`, `ui.fold.thinking`, `ui.fold.code` (`true`/`false`), `ui.fold.codeLines` |
| `ui.localizedDurations` (`"on"`/`"off"`) | `ui.durations` (`"words"`/`"clock"`) |
| `ui.timeout`, `ui.interruptKeys`, `ui.interruptSendsQueued` | `ui.showTimeout`, `ui.stopKeys`, `ui.queuedOnStop` |
| `ui.escapeInterruptRequiresConfirmation`, `ui.abortTurnRequiresConfirmation` | `ui.stopTwice` |
| `ui.jobAutoReturnWhenFocused` | `ui.leaveFinishedJob` |
| `ui.onlyUsefulModels` (`"on"`) | `ui.listAllModels` (`false`) |
| `keepAwake: "system"`, `keepAwake: "display"` | `keepAwake: "working"`, plus `keepDisplayAwake: true` for the display |
| `sandbox.denyRead`, `sandbox.allowRead`, `sandbox.allowWrite` | `sandbox.hide`, `sandbox.readable`, `sandbox.writable` |
| `approvals.scope` (`"narrowing-only"`) | `approvals.remember` (`"narrowing"`) |
| `skills.maxAdvertised` | `skills.maxListed` |

Switches are `true` or `false`; `"on"` and `"off"` are still read.

## Every setting

### Top level

| Key | Default | What it does |
|---|---|---|
| `model` | the provider's default | The model to use. `/model` changes it for the session. |
| `provider` | the first account that can answer | The connection to use: `anthropic`, `codex`, `agy`, `apple`, a named connection, or an entry of `providers.json`. See [Providers and accounts](providers.md). |
| `thinking` | `default` | How much the model thinks: `default` (whatever the provider does), `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. |
| `maxTurns` | `100` in the sandbox, no limit with `--no-sandbox` | The most model requests one prompt may make before ask stops it, or `null` for no limit (`ASK_MAX_TURNS=none`). A value you set applies in both cases. |
| `compactAt` | `0.75` | When the conversation is summarised to make room: a share of the model's window up to `1` (`0.75`, in whole percents), a number of tokens above it (`150000`), or `0` for only when the window is full. Whatever you set, ask compacts before a request would not fit. |
| `keepAwake` | `"working"` | When ask keeps the Mac from sleeping when idle: `"working"` while a prompt runs or a background job does, `"always"` for as long as ask runs, working or not, `"off"` never. Released as soon as there is no reason left, and when ask exits. It keeps the Mac from sleeping, not from restarting: to hold a restart or an update's restart while ask runs, turn on your terminal's own prompt before closing a window that runs a process (Terminal: Settings › Profiles › Shell › Ask before closing). |
| `keepDisplayAwake` | `false` | Whether the display stays on too, whenever `keepAwake` holds the Mac. |
| `sessionEncryption` | asked at first start | Whether new sessions are encrypted (ADR-0138): `"on"`, `"off"`, or `"ask"` when each begins. Encrypted sessions open only with your password or recovery code; ask shows the recovery code once, when it makes the keys. A workspace's file overrides yours either way. `/encrypt on` rewrites the current session encrypted and removes its pictures' unencrypted copies when no other session names them; the drive may still hold the file's old blocks until they are reused, as with any deleted file. |
| `sessionCompression` | `false` | Whether session files are compressed (about half their size). A compressed or encrypted file is no longer readable with `cat`. |
| `sessionPassword` | asked at first start | `"remember"` keeps the key your password opens in the keychain, so no password is asked at start; `"everyStart"` asks it at every start. |
| `taskScope` | `session` | Whose task list the `tasks` tool and `/tasks` use: each session's own (kept beside it, forked with it), or `"workspace"` for one list every session of the project shares. Kept as the session is: plain, compressed or encrypted. |
| `credentials` | `"auto"` | Where your API keys and sign-in tokens are kept: `"keychain"` in the macOS Keychain (only ask can read them without you being asked), `"file"` in `~/.config/ask/credentials.json`, or `"auto"`: the Keychain for a signed build of ask, the file for an unsigned one, whose every rebuild the Keychain would ask about. Emails, expiry dates and account names stay in the file either way. Changing it moves what is stored. Your own file only. |
| `presets` | none | Sets of MCP servers ask knows, added to the file's `mcp`: `["swift"]` connects apple-docs (Apple's documentation, from its public instance) and swift-search (your Swift code; it runs `swift-search mcp`, so it must be on your PATH). A server the file names itself wins, and a change such as `"mcp": {"apple-docs": {"enabled": false}}` applies to the preset's. A project's file may name a preset, as it may name servers: it is read only once you trust the project. |
| `modelScopes` | none | Which providers may serve a repository, by its folder, remote or git identity; the first rule that matches decides. See [`modelScopes`](#modelscopes). Your own file only. |
| `sandbox` | on, see below | What the model's tools may read, write and reach. |
| `ui` | see below | How the screen looks and behaves. |
| `skills` | see below | Which skills are offered to the model. |
| `mcp` | none | MCP servers whose tools are offered to the model. |
| `environment` | see below | What commands inherit from your environment, and which shell runs them. |

### `ui`

Switches take `true` or `false` (the older `"on"` and `"off"` still work).

| Key | Default | What it does |
|---|---|---|
| `mouse` | `true` | ask handles clicks, selection and the wheel. `false` leaves them to the terminal. |
| `copyOnSelect` | `true` | A finished selection is copied at once. |
| `fold` | see below | Which blocks start folded, as an object: `"fold": {"tools": false}`. |
| `fold.tools` | `true` | Tool calls start folded to one line (`false` shows their output). A compaction's summary starts folded either way, like thinking; a click or the fold key opens it. |
| `fold.thinking` | `true` | The model's reasoning starts folded to one line. |
| `fold.code` | `true` | Long code blocks start folded. |
| `fold.codeLines` | `20` | How many lines make a code block long (never more than half the screen). |
| `fold.outputLines` | `200` | A tool's output with more lines than this keeps its head and tail and folds its middle; a click on the marker, or Ctrl+G, shows it. At least 2. |
| `fold.outputBytes` | `32768` | The same, in bytes: each end keeps half. At least 64. |
| `scrollLines` | `3` | Lines per wheel step. |
| `inputRows` | `6` | How many rows the input grows to before it scrolls (at most a third of the screen). |
| `sidebar` | `"closed"` | Whether the runner sidebar starts `"open"` (wide screens only). |
| `sidebarLayout` | `"adaptive"` | Where the open sidebar goes: `"full"` beside the transcript, its whole height; `"bottom"` in a band with the input, six rows or more for many runners (at most a third of the screen), so the transcript keeps the whole width and the status line's counts move to its end; `"adaptive"` the band where the full sidebar would leave the transcript under 100 columns, beside it elsewhere. Screens under 18 rows keep it beside the transcript. |
| `sidebarJobs` | `"tree"` | Where the sidebar lists the jobs a thread started: `"tree"` under the thread, or `"section"` with every job in the Jobs section. `/sidebar jobs` switches it for the run. |
| `inputPrefix` | none | Text the input line starts with, such as `"> "`. By default the input is marked by its tint. |
| `tint` | `true` | Tinted backgrounds for the input, your messages and tool calls. |
| `appearance` | `"auto"` | Where the tints come from. `auto` mixes them, and the grey of secondary text, from your terminal's own colours and follows them when macOS switches between light and dark; `light` or `dark` fixes them and asks the terminal nothing. |
| `separator` | `true` | A rule between the conversation and the input. |
| `padding` | `true` | A row of padding around each block. |
| `markdown` | `true` | Markdown everywhere it can be: the model's replies and reasoning and your own messages are drawn as Markdown (headings, emphasis, lists, quotes, tables, links), and your draft is coloured as you type, every character kept as typed. A selection still copies what was written. `false` shows all of it as written. |
| `highlight` | `true` | Fenced code coloured by the language its fence names (` ```swift `, ` ```sh `, ` ```c++ `…), the text of a file `read` shows or `write` puts, by the file's extension (or its `#!` line), and a tool's output that is JSON or a unified diff (a diff's rows tinted as an edit's), in your terminal's own palette, so the colours follow its theme. A language ask does not know is drawn plain. `false` draws code in one colour. |
| `durations` | `"words"` | Elapsed times as `1 hr, 40 min` (`"words"`) or `1:40:00` (`"clock"`), and a command's limits as `timeout 2 min` or `timeout 2:00`. |
| `spinner` | `"line"` | The spinner: `line`, `snake`, `braille`, `braillefull`, `braillequarter` or `random`. A file that still says `dot` or `star` loads, and draws `line`. |
| `shimmer` | `true` | A running block's header shimmers: a brighter stretch moves along it with the spinner. `false` keeps it still. |
| `hover` | `true` | What a click acts on brightens under the pointer: a block's header, a job's row. The terminal then reports the pointer's moves; `false` asks it not to. Needs `mouse`. |
| `showTimeout` | `"auto"` | When a command's timeout is written in its header: `"auto"` only when the model chose one other than the 2-minute default, so the usual header is `shell · swift build`; `"always"` whenever the model set one; `"never"`. The time a command is left to run before it moves to the background (`yield`) is written unless this is `"never"`. |
| `timeoutLabel` | `"timeout"` | The word in front of a command's timeout, 1 to 8 characters: `"⏱"` writes `shell · ⏱ 5 min · swift build`. |
| `stopKeys` | `"both"` | Which keys stop a running turn: `"esc"`, `"ctrl-c"` or `"both"`. |
| `stopTwice` | `["esc"]` | The keys that must be pressed twice to stop a turn: `["esc"]`, `["esc", "ctrl-c"]`, `["ctrl-c"]` or `[]`. |
| `queuedOnStop` | `"all"` | What happens to messages you queued when you stop a turn: `"all"` sends them (the first starts a turn, the rest join it), `"next"` sends the first and keeps the rest queued, `"none"` puts them back in the input. |
| `leaveFinishedJob` | `true` | When a background job you are watching ends, go back to the conversation. |
| `listAllModels` | `false` | Model lists also show models ask cannot use (image, audio, completion-only, no tool calls), as `ask models --all` does. |
| `sessionColor` | `"off"` | A colour of the session's own as the status line's background, to tell sessions apart: `"always"`, seeded by the project's path and the session file's name so a session keeps its colour; `"others"`, the same colour only while another ask runs on this Mac; `"off"`. |

### `sandbox`

See [The sandbox](sandbox.md) for what it protects.

| Key | Default | What it does |
|---|---|---|
| `write` | `"workspace"` | Where tools and commands may write: `"workspace"` (the project, temporary directories, and the caches builds write: `~/Library/Caches`, Xcode's DerivedData, SwiftPM's), `"anywhere"`, or a list of directories. |
| `read` | `"anywhere"` | Where they may read: `"workspace"` (the project, the system and developer tools), `"anywhere"`, or a list of directories. The protected paths stay hidden either way. |
| `network` | `"any"` | How far commands reach: `"none"`, `"localhost"`, `"provider"` (only the model provider in use, through ask's proxy) or `"any"`. |
| `hide` | none | More paths to hide. |
| `readable` | none | Protected paths to make readable again, such as `"~/.aws"` or `"~/.config/gh"`. Your own file only. |
| `writable` | none | Protected paths to make writable again, such as `"~/.zshrc"`, or `".git/config"` for every repository (a relative entry is relative to the project). Your own file only. |

Any file can make `write`, `read` and `network` stricter; only the `--write`, `--read` and `--network` flags widen them.

### `skills`

See [Skills and MCP servers](skills-and-mcp.md).

| Key | Default | What it does |
|---|---|---|
| `enabled` | `true` | Whether skills are offered at all. |
| `maxListed` | `32` | How many skills are listed to the model; the rest can still be found and loaded by name. Your own file only. |
| `sources` | every harness | Where to look, by harness: `agents`, `ask`, `claude`, `codex`, `pi`, `opencode`, `vibe`, `copilot`, and `user`, `project` or `bundled`. Your own file only. |

### `mcp`

Each member names a server. Put servers in your own file; a project's file can name one only once you have trusted it.

| Key | What it does |
|---|---|
| `command`, `args`, `env`, `cwd` | A program ask starts, its arguments, extra variables (a value may be `${NAME}` for one of yours), and where it runs. |
| `url`, `headers` | A server at an address instead, and header fields to send (`"Authorization": "Bearer ${TOKEN}"`). |
| `tools` | Only these of its tools, by the server's names. |
| `enabled` | `false` keeps the entry without connecting. |
| `mode` | `"direct"` offers its tools directly, `"search"` through a search tool. By default, a server with more than 16 tools is searched. |
| `maxDirectTools` | Changes that threshold of 16 for this server. |

In a project's file, an entry with no `command` and no `url` changes the server of that name in your file instead of replacing it, and may
set only `enabled`, `tools`, `mode` and `maxDirectTools`. `{"mcp": {"xcode": {"enabled": false}}}` turns your `xcode` server off in that
project and leaves your others alone. It cannot change what runs or what it is given (`args`, `env`, `cwd`, `headers`); an entry naming no
server of yours is ignored, with a notice. `ask trust` lists what such an entry changes.

### `approvals`

Before a call that changes things runs, ask asks you: a command, writing or editing a file, typing into a job. Reading, searching and
listing never ask, and MCP tools ask unless their server says they are read-only. You answer **Allow this time**, **Allow for the
session** (for a command: the same subcommand, `git status`; or the program, `git`; for a file: that file), or **Deny**. `ask -p` asks
nothing: running it was the consent. `--allow commands` (every command), `--allow all` (every call, the same as `--yes`) or `--allow
write` add to `allow` for one run; `--ask NAME` adds to `ask`, and `--ask all` asks before every call that changes things, even what
this section allows (it was `--ask-always`); `--yolo` is `--no-sandbox` and `--yes` together; the sandbox
still asks about anything beyond it either way. Your own file only.

| Key | Default | What it does |
|---|---|---|
| `default` | `"ask"` | What a call no list names does: `"ask"`, or `"allow"` to run it. |
| `allow` | none | Tools that run without asking: `["bash", "mcp__docs__*"]`; `"commands"` allows every command, `"all"` every tool call. A name ending in `*` covers every tool that starts with the rest. |
| `ask` | none | Tools that always ask, read-only ones included: `["read"]`. Wins over `allow`. |
| `remember` | `"none"` | What an "always" answer could write back to this file: `"anything"`, `"narrowing"` or `"none"`. No answer writes the file yet. |

### `hooks`

Hooks are code that sees what a run does (roadmap 0192). When a run would end, a hook can send the model a message and keep it going,
to have it fix the tests it broke, for example. The message is recorded as yours, labelled `[hook name]`, and the transcript says when a
hook continued a run or a limit stopped it. A trusted project's file may set `check` and `checkTimeout`, since the right command is
the repository's.

| Key | Default | What it does |
|---|---|---|
| `maxContinues` | `3` | How many times hooks may continue one run that would have ended, from 0 to 100; 0 never lets them. Each also counts against `maxTurns`. Your own file only. |
| `check` | none | A command, such as `"swift test"`, run when a run that wrote, edited or ran a command would end. It runs in the session's sandbox without asking you, shown as a `check` block while it runs, and when it fails its output's end goes back to the model to fix. A pass, or a run that only read, ends the run. |
| `checkTimeout` | `600` | How many seconds the check may take, from 1 to 600; past it the check is stopped and the run simply ends. |

### `threads`

Threads are copies of the conversation that work beside it (`/thread`, roadmap 0195). These keys limit them and say how they are
named; a project's file may set them too, since they only ever limit what runs.

| Key | Default | What it does |
|---|---|---|
| `max` | `4` | How many threads may work at once, from 1 to 16; `/thread` past it is refused until one finishes or is stopped. |
| `depth` | `3` | How deep threads may nest, from 1 to 8; `/thread` in a thread that deep is refused. |
| `merge` | `"auto"` | Whether a thread that finished merges back on its own (`"auto"`), or asks first (`"ask"`). Declined, it stays unmerged, marked `○`: typing in its lane goes on with it, and `/merge` there merges it. A thread that failed or was stopped always asks. |
| `model` | the conversation's model | The model threads work with and write their summaries with, written as `/model` takes it: `"provider/model"` or a model, such as a cheaper or faster one. A model that does not resolve fails the thread, saying why. |
| `summaryInstructions` | none | What every thread's summary should also hold, added after the standard merge instruction, such as `"List every file you changed."` |
| `mergedShownFor` | `"1d"` | How long a merged thread stays in the sidebar: `"30m"`, `"2h"`, `"1d"`, or `"always"`. After it, `/threads` still lists it; the list below the input never shows merged threads. |
| `questions` | `"focus"` | Where a thread's approval or question appears while you are elsewhere: `"focus"` at once where you are, named for the thread (answering it there answers the thread); `"after"`, the same once it has waited `questionsAfter`; or `"lane"`, only in its lane. Your own conversation's questions come first. |
| `questionsAfter` | `"30s"` | How long `"after"` waits: seconds, minutes or hours, such as `"30s"` or `"2m"`. |
| `names` | `"onDevice"` | How a thread is named: `"onDevice"`, by Apple's on-device model from its task, where it is available (`thread-N` elsewhere), `"model"`, by a provider's model (`namesModel`), or `"numbered"`. `/rename` in a thread's lane names it yourself. |
| `namesModel` | the conversation's model | The model `names` `"model"` asks for a thread's name, written as `/model` takes it: `"provider/model"` or a model. Empty, the conversation's own model. A name that does not come in 15 seconds is not waited for. |

### `agents`

Subagents (roadmap 0063, ADR-0146): the model may start a thread of its own with the `agent` tool, giving it a task, what it needs
to know and what counts as done; it sees nothing else of the conversation, and its summary is the call's result. Off unless your
own file turns it on: a project's may turn it off, never on, and may not let subagents write.

| Key | Default | What it does |
|---|---|---|
| `enabled` | `false` | Whether the model has the `agent` tool. Off, no request carries it and nothing on screen names one. Your own file only. |
| `allowWrites` | `false` | Whether subagents may change files; read-only otherwise, whatever the parent may do. Your own file only. |
| `maxTurns` | `30` | The most turns one subagent may take, from 1 to 200. |

Agent definitions are Markdown files in `~/.config/ask/agents` (`NAME.md`): a head with `description`, and optionally `name`, `tools`
and `model`, then the instructions. The `agent` tool lists them, and a call may name one: the subagent is told its instructions before
its task, and keeps only the tools it names (none named, it keeps all of a subagent's). `model` is read but not yet used.

### `modelScopes`

A list of rules that limit which providers serve a repository: work repositories only through the work account, say. Each rule names
one or more of `path` (the project's folder and everything beneath it; `~` is your home folder), `remote` (any of the repository's
remote URLs) and `identity` (the `user.email` or `user.name` the repository commits as, from its own git config, then
`~/.gitconfig`, then `~/.config/git/config`), and `providers`, the connections and providers allowed there. Every matcher a rule
names must match, and the first rule that matches decides; when none does, every provider may serve. Patterns ignore case; `*`
stands for any run of characters, `/` included, and `?` for one.

```jsonc
"modelScopes": [
  {"path": "~/work", "providers": ["work", "codex"]},
  {"remote": "*github.com?acme/*", "identity": "*@acme.com", "providers": ["acme"]}
]
```

Where a rule applies, `/model`, `ask models` and the choice of a default model leave out the other providers, and `--provider`,
`--model` or `/model` naming one of them is refused with the rule's number: the rules are a policy, not a preference, so no flag
overrides them. Edit or remove the rule instead. Git's files are read directly, without starting git; a folder outside any
repository has no remote, and `include` lines in a git config are not followed. Your own file only: a project's file cannot set it.

### `environment`

| Key | Default | What it does |
|---|---|---|
| `withhold` | ask's and well-known credential variables | More variables to keep from commands, by name or with `*` (`"AWS_*"`). A project's file may add to it. |
| `pass` | none | Variables ask withholds that commands should get anyway. Your own file only. |
| `shell` | the first bash on your PATH, else `/bin/bash`, else ksh, sh or dash, else your login shell | The shell commands run in: a name, or an absolute path from `/etc/shells`. Your own file only. Each command is parsed by that shell before it runs, and not run when it does not parse; with bash or sh, shellcheck's findings (when it is installed) come with a failed command's result. |

Commands get your environment except the credentials ask knows of: its own, `ANTHROPIC_*` and `ASK_*`, and well-known credential
variables of other tools and services, such as `GITHUB_TOKEN`, `GH_TOKEN`, `AWS_SECRET_ACCESS_KEY`, `OPENAI_API_KEY` and `NPM_TOKEN`.
A tool's other settings (`AWS_REGION`, `AWS_PROFILE`) still reach it. If `gh` or `aws` should use the token in your environment,
pass it: `"pass": ["GH_TOKEN"]`. A secret ask does not know of is passed on unless you withhold it. `/config` shows the policy, never
the values.
