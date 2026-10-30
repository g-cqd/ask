# Configuration

ask works without any configuration. When you want to change something, put it in a `config.json`:

- `~/.config/ask/config.json` for you, everywhere (or `$XDG_CONFIG_HOME/ask/config.json`);
- `.ask/config.json` in a project, for that project only.

The file is JSON, or JSON5 if you like comments, unquoted keys and trailing commas. Set only what you want to change; everything else keeps
its default. To see what is in force and where each value came from, run:

```sh
ask config
```

Inside ask, `/config` opens an editor for the same settings, and `/config now` re-reads the files and shows them. ask watches the files while it
runs: a saved change applies at once between turns, or as soon as the running turn ends, and your draft is left as it is (`/verbose`
lists what changed). A project file is noticed even when its `.ask` folder did not exist when ask started. If an edit is broken, ask
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
{ ui: { tools: "open", thinking: "open" } }
```

A plainer screen, with no tinted blocks, padding or separator:

```json5
{ ui: { tint: "off", padding: "off", separator: "off" } }
```

Let the terminal handle the mouse (its own selection and scrolling):

```json5
{ ui: { mouse: "off" } }
```

Make one Esc enough to stop a running turn, or keep Esc out of it entirely:

```json5
{ ui: { escapeInterruptRequiresConfirmation: "off" } }   // one Esc stops the turn
{ ui: { interruptKeys: "ctrl-c" } }                       // only Ctrl+C stops it
```

Compact the conversation earlier, at half of the model's context window:

```json5
{ compactAt: "50%" }
```

Keep commands from writing outside the project, and off the network:

```json5
{ sandbox: { write: "workspace", network: "none" } }
```

Let commands read `~/.aws` (hidden by default), in your own file:

```json5
{ sandbox: { allowRead: ["~/.aws"] } }
```

Run commands with fish instead of zsh:

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
   `--no-sandbox`, `--yes`, `--ask-always`.

Inside a section such as `ui`, a layer replaces only the keys it sets.

**A project's file is ignored until you trust it.** It comes from a repository, so it could have been written by anyone. Run `ask trust` in
the project, at a terminal, to trust it as it is now; if it changes, it is ignored again until you trust it again. `ask untrust` stops
trusting it. Some settings can only come from your own file, as the tables below say.

## Every setting

### Top level

| Key | Default | What it does |
|---|---|---|
| `model` | the provider's default | The model to use. `/model` changes it for the session. |
| `provider` | the first account that can answer | The connection to use: `anthropic`, `codex`, `agy`, `apple`, a named connection, or an entry of `providers.json`. See [Providers and accounts](providers.md). |
| `thinking` | `default` | How much the model thinks: `default` (whatever the provider does), `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. |
| `maxTurns` | `100` in the sandbox, none with `--no-sandbox` | The most model requests one prompt may make before ask stops it, or `"none"` for no limit (also `ASK_MAX_TURNS=none`). A value you set applies in both cases. |
| `compactAt` | `"75%"` | When the conversation is summarised to make room: a share of the model's window (`"75%"`), a number of tokens (`150000`), or `0` for only when the window is full. Whatever you set, ask compacts before a request would not fit. |
| `keepAwake` | `"system"` | While a prompt runs or a background job does, `"system"` keeps the Mac from sleeping when idle, `"display"` keeps the display on too, `"always"` keeps the Mac from sleeping when idle for as long as ask runs, working or not, `"off"` does nothing. Released as soon as ask stops working, and when it exits. |
| `credentials` | `"auto"` | Where your API keys and sign-in tokens are kept: `"keychain"` in the macOS Keychain (only ask can read them without you being asked), `"file"` in `~/.config/ask/credentials.json`, or `"auto"`: the Keychain for a signed build of ask, the file for an unsigned one, whose every rebuild the Keychain would ask about. Emails, expiry dates and account names stay in the file either way. Changing it moves what is stored. Your own file only. |
| `sandbox` | on, see below | What the model's tools may read, write and reach. |
| `ui` | see below | How the screen looks and behaves. |
| `skills` | see below | Which skills are offered to the model. |
| `mcp` | none | MCP servers whose tools are offered to the model. |
| `environment` | see below | What commands inherit from your environment, and which shell runs them. |

### `ui`

Switches take `"on"` or `"off"` (`true` and `false` work too).

| Key | Default | What it does |
|---|---|---|
| `mouse` | `"on"` | ask handles clicks, selection and the wheel. `"off"` leaves them to the terminal. |
| `copyOnSelect` | `"on"` | A finished selection is copied at once. |
| `tools` | `"folded"` | Tool calls start folded to one line (`"open"` shows their output). |
| `thinking` | `"folded"` | The model's reasoning starts folded to one line. |
| `code` | `"folded"` | Long code blocks start folded. |
| `codeFoldLines` | `20` | How many lines make a code block long (never more than half the screen). |
| `scrollLines` | `3` | Lines per wheel step. |
| `promptRows` | `6` | How many rows the input grows to before it scrolls (at most a third of the screen). |
| `sidebar` | `"closed"` | Whether the runner sidebar starts `"open"` (wide screens only). |
| `prompt` | none | Text the input line starts with, such as `"> "`. By default the input is marked by its tint. |
| `tint` | `"on"` | Tinted backgrounds for the input, your messages and tool calls. |
| `appearance` | `"auto"` | Where the tints come from. `auto` mixes them, and the grey of secondary text, from your terminal's own colours and follows them when macOS switches between light and dark; `light` or `dark` fixes them and asks the terminal nothing. |
| `separator` | `"on"` | A rule between the conversation and the input. |
| `padding` | `"on"` | A row of padding around each block. |
| `markdown` | `"on"` | Markdown everywhere it can be: the model's replies and reasoning and your own messages are drawn as Markdown (headings, emphasis, lists, quotes, tables, links), and your draft is coloured as you type, every character kept as typed. A selection still copies what was written. `"off"` shows all of it as written. |
| `localizedDurations` | `"on"` | Elapsed times as `1 hr, 40 min` rather than `1:40:00`, and a command's limits as `timeout 2 min` rather than `timeout 2:00`. |
| `spinner` | `"line"` | The spinner: `line`, `dot`, `star`, `snake`, `braille`, `braillefull`, `braillequarter` or `random`. |
| `timeout` | `"auto"` | When a command's timeout is written in its header: `"auto"` only when the model chose one other than the 2-minute default, so the usual header is `shell · swift build`; `"always"` whenever the model set one; `"never"`. The time a command is left to run before it moves to the background (`yield`) is written unless this is `"never"`. |
| `timeoutLabel` | `"timeout"` | The word in front of a command's timeout, 1 to 8 characters: `"⏱"` writes `shell · ⏱ 5 min · swift build`. |
| `interruptKeys` | `"both"` | Which keys stop a running turn: `"esc"`, `"ctrl-c"` or `"both"`. |
| `escapeInterruptRequiresConfirmation` | `"on"` | Esc must be pressed twice to stop a turn. |
| `abortTurnRequiresConfirmation` | `"off"` | Ctrl+C must be pressed twice to stop a turn. |
| `interruptSendsQueued` | `"all"` | What happens to messages you queued when you stop a turn: `"all"` sends them (the first starts a turn, the rest join it), `"next"` sends the first and keeps the rest queued, `"none"` puts them back in the input. |
| `jobAutoReturnWhenFocused` | `"on"` | When a background job you are watching ends, go back to the conversation. |
| `onlyUsefulModels` | `"on"` | Model lists leave out models ask cannot use (image, audio, completion-only, no tool calls). |

### `sandbox`

See [The sandbox](sandbox.md) for what it protects.

| Key | Default | What it does |
|---|---|---|
| `write` | `"anywhere"` | Where tools and commands may write: `"workspace"` (the project and temporary directories), `"anywhere"`, or a list of directories. |
| `read` | `"anywhere"` | Where they may read: `"workspace"` (the project, the system and developer tools), `"anywhere"`, or a list of directories. The protected paths stay hidden either way. |
| `network` | `"any"` | How far commands reach: `"none"`, `"localhost"` or `"any"`. |
| `denyRead` | none | More paths to hide. |
| `allowRead` | none | Protected paths to make readable again, such as `"~/.aws"`. Your own file only. |

Any file can make `write`, `read` and `network` stricter; only the `--write`, `--read` and `--network` flags widen them.

### `skills`

See [Skills and MCP servers](skills-and-mcp.md).

| Key | Default | What it does |
|---|---|---|
| `enabled` | `"on"` | Whether skills are offered at all. |
| `maxAdvertised` | `32` | How many skills are listed to the model; the rest can still be found and loaded by name. |
| `sources` | every harness | Where to look, by harness: `agents`, `ask`, `claude`, `codex`, `pi`, `opencode`, `vibe`, `copilot`, and `user`, `project` or `bundled`. |

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

### `approvals`

Before a call that changes things runs, ask asks you: a command, writing or editing a file, typing into a job. Reading, searching and
listing never ask, and MCP tools ask unless their server says they are read-only. You answer **Allow this time**, **Allow for the
session** (for a command: the same subcommand, `git status`; or the program, `git`; for a file: that file), or **Deny**. `ask -p` asks
nothing: running it was the consent. `--yes` allows every call for one run, `--ask-always` asks even what this section allows; the sandbox
still asks about anything beyond it either way. Your own file only.

| Key | Default | What it does |
|---|---|---|
| `default` | `"ask"` | What a call no list names does: `"ask"`, or `"allow"` to run it. |
| `allow` | none | Tools that run without asking: `["bash", "mcp__docs__*"]`. A name ending in `*` covers every tool that starts with the rest. |
| `ask` | none | Tools that always ask, read-only ones included: `["read"]`. Wins over `allow`. |
| `scope` | `"none"` | What an "always" answer could write back to this file: `"anything"`, `"narrowing-only"` or `"none"`. No answer writes the file yet. |

### `environment`

| Key | Default | What it does |
|---|---|---|
| `withhold` | ask's credential variables | More variables to keep from commands, by name or with `*` (`"AWS_*"`). A project's file may add to it. |
| `pass` | none | Variables ask withholds that commands should get anyway. Your own file only. |
| `shell` | zsh, else bash, else your login shell | The shell commands run in: a name, or an absolute path from `/etc/shells`. Your own file only. |

Commands get your environment except the credentials ask knows of, `ANTHROPIC_*` and `ASK_*`. A secret ask does not know of is passed on
unless you withhold it. `/config` shows the policy, never the values.
