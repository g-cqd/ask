# Skills first, then agent lanes: the design, the evidence, and the questions

> **Owner's answers, 2026-10-24** (the questions at the end are kept as asked; this is what was decided):
> 0. Bundled skills: **yes**, the model may pick them with `from`. A directory in `from` stays user-only.
> 1. Subagent defaults (read-only children, depth 1, `agents.enabled` user-level only): accepted.
> 2. Models in other providers: as recommended (not followed unless that connection is configured and `agents.allowOtherProviders` is on).
> 3. Comment hints and unresolved model or tool tokens: no fixed answer from the owner. **Use an available model, a very cheap one, to classify
>    or parse the list against ask's own list** when the deterministic match fails. Recorded below as *model-assisted resolution*.
> 4. Lane focus and keys: refined into the key model in roadmap 0064 and 0062 (Down from an empty draft or the last line; one input slot
>    that sends to the focused lane; Esc returns to the input, then to main; Ctrl+C clears the input and does not quit; a separate stop).
> 5. Sidebar: **open by default in the workbench layout, toggleable.**
> 6. Child sessions: **separate files.**

2026-10-24, from the owner's direction: **skills matter more than subagents; subagents are off by default; a subagent lane is focusable;
agents and the subagents of subagents show below the input, as Claude Code's panel does, and as a tree in a sidebar too.** This note is the
review of all of that. Nothing in it is built. The decisions are written as *proposed*, with the reason, so each can be accepted or
overruled; the three roadmap entries that follow from it are 0061 (skills), 0062 (the runner tree, lanes and sidebar) and 0063 (subagents).

## What was read, and what was not

Read: the roadmap entries 0027, 0033, 0048, 0049, 0051 and 0015, ADR-0032 (trust), ADR-0066 (the runner seam), the `/` and `@` pickers as
built, `ProjectInstructions`, `SessionPayload`, Pi's skills documentation, and the research note on other agents' UIs.
**Not observed:** how Claude Code's panel behaves. The research note records it from the vendor's documentation ("a panel under the prompt
for forks and subagents; opening one sends your messages to it"), and none of its views were seen running. Anything below that says
"as Claude Code does" is that sentence and no more.

## One probe that was run: the owner's own skills

`~/.agents/skills` holds 26 skills (`~/.claude/skills` is a symlink to the same set; the two must be deduplicated by real path, or every
skill is advertised twice). Parsed with a quick script, not ask's code:

| Fact | Value | What it forces |
|---|---|---|
| Skills | 26, all `SKILL.md` in a directory | The discovery rule is "a directory containing `SKILL.md`" |
| Frontmatter keys | `name`, `description` (all 26); `allowed-tools` (21); `metadata` (3) | `allowed-tools` is common, so its meaning has to be decided, not skipped |
| Name differs from directory | 1 of 26 (`"openai-docs"` is **quoted** in the file) | The reader must accept quoted values; folding (`>-`) and multi-line descriptions occur too |
| Symlinked skill directories | at least 4 | Discovery follows symlinks; a symlink must not escape the trust decision |
| Cost of *advertising* them (name + description + path, characters / 4) | about 11,400 characters, **about 2,850 tokens** per request | Needs a cap and a way to turn skills off; it is paid on every request unless prompt caching holds the prefix still |
| `SKILL.md` size | median 11.7 KB, maximum 31 KB | Bodies must be loaded on demand, never advertised; a 31 KB body is about 8k tokens |

The token figure is a character count divided by four, not a tokenizer's count, and it is for one person's collection; it says the cost is
real and in the thousands, not what it is exactly.

## Skills (roadmap 0061)

**What a skill is.** The Agent Skills form, which Pi, Claude Code and Codex share: a directory with `SKILL.md`, frontmatter with `name` and
`description`, optional `scripts/`, `references/`, `assets/`. Descriptions are routing text for the model; bodies load on demand.

**Proposed decisions**

1. **Discovery reads every harness's locations, unless told otherwise** (owner's direction, 2026-10-24). The default is the union of the
   user-level and project-level skill directories of each harness ask knows, **deduplicated by real path**, then by name. The sources, each
   with an id the user and the tool can name:

   | Source id | User-level | Project-level | Seen on the owner's machine |
   |---|---|---|---|
   | `agents` | `~/.agents/skills` | `.agents/skills` (working directory up to the repository root) | yes, and `.agents/skills` in 2 project trees |
   | `ask` | `~/.config/ask/skills` | `.ask/skills` | not yet (ask has none) |
   | `claude` | `~/.claude/skills` | `.claude/skills` | yes (a symlink) |
   | `codex` | `~/.codex/skills` | `.codex/skills` | yes (a symlink) |
   | `pi` | `~/.pi/agent/skills` | `.pi/skills` | yes (a symlink) |
   | `opencode` | `~/.config/opencode/skills` | `.opencode/skills` | yes (a symlink) |
   | `vibe` | `~/.vibe/skills` | `.vibe/skills` | yes (a symlink) |
   | `copilot` | `~/.copilot/skills` | `.github/skills` | yes (a symlink); `.github/skills` also exists in `~/vcpkg` and a VS Code extension, found by a wider search, and in none of the projects under `~/Developer` |
   | `agy` | `~/.gemini/config/skills`, plus its bundled `~/.gemini/antigravity-cli/builtin/skills` | `.gemini/skills` | yes: a symlink, and **9 bundled skills that exist nowhere else** |

   The locations seen on disk are a fact about this machine. The project-level paths for harnesses other than `agents` are from those tools'
   documentation or convention, were not found in any project here (the search looked in `~/Developer`, four levels deep), and are
   **proposals until each is checked against a real project**. A table in code is the right shape: adding a harness is one row.

   **What the owner's machine shows:** eight harness directories (`claude`, `agents`, `codex`, `pi`, `opencode`, `vibe`, `copilot`, `agy`) are
   **symlinks to one canonical `~/.agent-harness/skills`**, so the union of all of them is the same 26 skills seen eight times. Real-path
   deduplication is therefore not an optimisation but what keeps the advertisement from being eight times too long. Beyond them are the
   bundled `agy` skills (9, no overlap by name), `~/.agent-harness/xcode-skills` (10, no overlap) and per-extension or per-plugin skill
   directories (VS Code extensions, a Codex plugin cache, a package cache). **Bundled and plugin-cache directories are a separate source
   (`bundled`) and are off by default**: they belong to a tool, change with its updates, and are not the user's. Everything else is on.

   **Narrowing with an argument.** The `skill` tool takes an optional `from`: a source id or a list of them (`"codex"`, `["claude", "agents"]`),
   a project/user qualifier (`"project"`, `"user"`), and nothing else. The same narrowing exists for the user in `ask --skills-from`, in
   `skills.sources` in the configuration (which may also name **directories**), and in `/skill:name --from claude`. The model's argument
   can only **narrow**: it cannot name a path, because a path would make the tool a way to read anything. A directory is accepted only from the
   user's own configuration or command line. When two sources have a skill of one name, the order above is the precedence, the loser is
   reported by `ask skills`, and `from` is how to get the other one; identical files (same bytes) are one skill with no report.

2. **Advertise name, description and path** in the system prompt, in a **stable order** (sorted by name) so the prompt-cache prefix does not
   change between requests, and **capped** (`skills.maxAdvertised`, and a per-description cut at 1,024 characters as the spec says). Over the cap, the
   list says how many are not shown; it never silently drops.
3. **The model loads a skill with a `skill` tool**, not by reading the file. Reasons: the result is a normal tool result, so **no change to the
   closed `SessionPayload`** and resume replays it for free; it works under `read: 'workspace'`, where `~/.agents` is unreadable; the tool can
   say where the skill lives so relative paths resolve; and it costs one small tool definition. Bundled `references/` and `scripts/` are then
   read or run with the ordinary tools, under the ordinary sandbox: **a skill grants no permission** (ADR-0048's rule, kept).
4. **`/skill:name args`** forces a skill, and skills join the `/` picker with `SKILL` and `PROJECT` labels, exactly as ADR-0048 sketched.
   A built-in command wins a name collision; the skill stays reachable under `/skill:`. `disable-model-invocation: true` hides a skill from the
   advertisement but not from `/skill:`.
5. **Trust.** User skills load. **Project skills load only when the project is trusted** (ADR-0032's mechanism, extended from one file's hash
   to the set of `SKILL.md` files: names and SHA-256s), and a changed skill is untrusted until looked at again. A project's configuration may
   narrow (turn skills off) and never widen.
6. **`allowed-tools` is read, shown, and ignored.** Pi calls it experimental; honouring it would let a skill file widen what runs without
   approval, which ADR-0054 forbids (a call may narrow and never widen) and ADR-0055 routes to the user. `ask skills` says "this skill asks for X; ask grants nothing".
7. **Errors are diagnostics, not startup failures**: a malformed skill is listed with its reason by `ask skills` and `/skills`.
8. **`/reload` and `ask skills`** list what was found, from where, trusted or not, with the cost of the advertisement in tokens (estimated).

**Why before subagents.** It is the smaller change (no loop concurrency, no UI lanes), it is the one the owner's own habits already depend
on (26 skills in daily use), it adds no way to spend money unattended, and it exercises the pieces subagents also need: a trusted-source
rule, a `/` picker kind, a per-request prompt-cost budget, and a model-visible tool whose result is recorded as ordinary history.

## Parsing skills, agents, tools and models as permissively as possible (roadmap 0061, 0063)

**The rule.** A file that a person or another harness wrote is read for what it can give; it is never rejected for how it is written.
The parser **cannot fail**: it returns the fields it understood and a list of diagnostics, and a skill is skipped only when there is nothing to
derive a name and a description from. Another harness's strictness is not ask's: Pi drops a malformed skill and Anthropic's validators insist
the name match its directory; ask loads them and says what it saw.

**Evidence: the owner's 147 files.** Parsed with a throwaway script over every `SKILL.md` and agent definition reachable from the harness
directories above (skills, `xcode-skills`, `agy` bundled skills, the Codex and VS Code bundled ones, and 14 agent definitions in each of
six harness formats). Every file has a frontmatter, 28 are TOML, and the **shapes are all different**:

| Field | Shapes found | Examples (verbatim) |
|---|---|---|
| `tools` | comma-separated string (Claude), YAML flow list (Copilot), YAML block list with **another harness's tool names** (Antigravity) | `Read, Grep, Glob, LSP, Bash, WebFetch, WebSearch, Skill, mcp__apple-docs` · `["read", "search", "web", "skill", "apple-docs/*"]` · `- view_file` `- grep_search` `- run_command` |
| `allowed-tools` | block list (21 of 26 skills) | `- Read` `- Glob` `- Grep` |
| `disallowedTools` | comma-separated string | `Edit, Write, NotebookEdit` |
| `model` | one alias; a flow list of **display names**; an alias followed by a **comment that holds fallbacks** | `opus` + `# fallback_models: claude-opus-5-5, claude-opus-4-8, sonnet` · `["Claude Opus 5.5", "GPT-6 Astra", "Claude Sonnet 5", "GPT-5.5"]` |
| `description` | plain, quoted, block scalar (`>-`, `|`), a plain scalar containing commas and colons | 85 of 104 are block scalars |
| `name` | plain, and **quoted** (`"openai-docs"`) | |
| other keys carried | `effort`, `reasoningEffort`, `maxTurns`, `steps`, `mode`, `permission`, `subagent`, `skills`, `hooks`, `inheritMcp`, `inheritCustomizations`, `color`, `background`, `argument-hint`, `when_to_use`, `disable-slash-command`, `metadata` | |

**The contract, each line a test (and the real corpus a probe: zero rejected):**

1. **Container.** A byte-order mark, CRLF, blank lines before the opening fence, `---` or `+++` fences with trailing spaces; a TOML file
   (Codex agent definitions) read as TOML; a file with **no frontmatter** is a skill named for its directory whose description is its first
   heading or paragraph. `SKILL.md` is matched case-insensitively. A bare `name.md` in a skills directory is a skill only if its frontmatter
   has a `description` (so a stray `README.md` is not).
2. **Structure.** Plain, single- and double-quoted scalars with escapes; `|` and `>` block scalars with any chomping or indentation indicator;
   flow lists and maps, across lines; block lists indented or not; nested maps; full-line and trailing comments, **outside quotes only**;
   tabs; duplicate keys (the last wins, and the duplicate is a diagnostic). If structured parsing fails partway, the rest is read line by
   line as `key: value`.
3. **Keys.** Compared case-insensitively with `-`, `_` and spaces ignored: `allowed-tools`, `allowed_tools`, `allowedTools` and `Allowed Tools`
   are one key. **Unknown keys are kept** with their values and shown by `ask skills --verbose`; none is an error.
4. **Tool lists** (`tools`, `allowed-tools`, `disallowedTools`) are an **ordered list of tokens** from a list *or* a scalar. A scalar splits on
   commas, newlines and whitespace **outside parentheses and brackets**, so `Bash(git diff:*)` is one token. Bullets, quotes and surrounding
   punctuation are stripped. Wildcards (`apple-docs/*`) and namespaced names (`mcp__apple-docs`) are kept whole. Each token is looked up,
   case-insensitively and ignoring punctuation, in an **alias table that is data, not code** (`Read`, `view_file` → `read`; `Bash`, `Shell`,
   `run_command` → `bash`; `Edit`, `MultiEdit`, `NotebookEdit` → `edit`; `Skill` → `skill`; `Task`, `Agent` → `agent`; and so on, one row per
   spelling seen). **A token ask does not know is kept verbatim, reported as unmapped, and never an error.** Tools are a vocabulary
   per harness, so unmapped is the normal case, not the failure case.
5. **What a tool list means, so permissiveness cannot widen anything.** A list is *only ever a restriction or a note*: it can select among tools
   ask already offers to that skill or child, and it can never add one. A skill's `allowed-tools` is shown and ignored (ADR-0054, ADR-0055). A
   subagent's `tools` narrows its read-only default; a list that maps to nothing leaves the default and says so; `disallowedTools` removes.
   An unrecognized token therefore costs nothing and grants nothing.
6. **Models** (`model`, and a `fallback_models` hint, whether a key or a trailing comment as in the corpus) are an **ordered preference list**
   read from a scalar or a list, with the same splitting rules. A token is `inherit`, `default` or empty (the parent's model); an **alias**
   (`opus`, `sonnet`, `haiku`, `fast`, `small`), matched to the newest model of that family the **active connection** lists; a **display name**
   (`Claude Opus 5.5`) or **id** (`claude-opus-5-5`), matched by lower-casing and dropping everything that is not a letter or digit, against
   both the ids and the display names the catalog gives; or a **provider-qualified** form (`anthropic/…`, `provider:model`). The first token
   that resolves wins; if none does, the parent's model is used and a notice says which token was tried. **It never fails, and it never leaves
   the current connection on its own:** a token naming another provider's model is a candidate only if the user has configured that
   connection and `agents.allowOtherProviders` is on (off by default), because a child that quietly sends the task to another company
   is a different decision from reading a model name.
7. **Names and sizes.** Any non-empty name loads; a name outside the spec's lowercase-and-hyphens form, or different from its directory,
   is a diagnostic only. A description over 1,024 characters is cut **in the advertisement** and whole in the tool's result.
8. **Never crash.** A property test feeds arbitrary bytes and arbitrary truncations of the corpus's shapes and requires: no trap, no hang
   (a bound on work per file), and the same result when run twice. Files are capped (the instruction-file cap, 64 KiB, is the precedent) and
   binary files are skipped with a reason.

**Agent definitions use the same reader** (0063): the 14 definitions in each of six harness formats are the evidence that "named agents
from other harnesses" is a real input, and that reading them permissively is most of the work. Whether ask loads another harness's agents at all
is still the open question in 0063; if it does, they arrive through this parser with the same rules, and `tools`, `model`, `maxTurns`/`steps` and
`effort`/`reasoningEffort` map onto ask's own limits and thinking level (roadmap 0053) where they match and are kept as notes where not.

## Model-assisted resolution (owner's answer to question 3; roadmap 0061 phase 5 and 0063)

When the deterministic reading fails (a model token that matches nothing on the active connection, a tool token that is in no alias row), ask
may put the token list and **ask's own list** to a **very cheap model on the active connection** and take its classification. Proposed bounds:

- **Deterministic first.** Aliases, display names, ids and the tool table decide whatever they can; the model sees only what they could not.
- **It sees tokens and ids, never content.** The request holds the unmatched tokens and the list of candidate model ids or tool names. No skill
  body, no project text, no conversation.
- **It can only choose among ask's own list or answer "none".** Its output is validated against that list; anything else is "none". It cannot add
  a tool, widen a permission, or name a model that is not in the catalog, so a wrong or hostile answer costs a worse match and nothing more.
- **Cached by the question.** The answer is stored beside the credentials, keyed by the tokens and a hash of the candidate list, so it is asked
  once per change and never at startup. A refresh of the catalog invalidates it.
- **Lazy and optional.** Asked the first time a child needs a model or a tool list needs resolving, never on the startup path; offline, signed out,
  or on failure it falls back to the parent's model and says so.
- **Which model.** The cheapest the connection offers: `classifier.model` in the configuration if set, else the smallest known family on the active
  connection (a table, one row per provider, `haiku`-class for Anthropic, `mini`-class for OpenAI-compatible and Codex). Not guessed from a model's name alone
  when the catalog says otherwise. Whether it is on by default, or off until the user enables it, is **not yet decided**: it spends the user's tokens
  on a call they did not type, however small.
- **Skills do not need it:** a skill's tool list is only shown, so unmapped tokens are reported and nothing else. It matters for subagents (0063).

## The runner tree, lanes below the input, and the sidebar (roadmap 0062)

**One model, three views.** ADR-0066's `RunnerInfo` is a flat list of jobs. It becomes a **tree of runners**: each has an id, a parent id (nil
for a top-level runner), a kind (`job`, later `agent`), a state (`running`, `waiting for approval`, `done`, `failed`, `stopped`), and one line of
what it is doing. The composition root sends the whole tree, as it sends the list today. The status line's count, a **lane strip below the
input**, and a **sidebar** are three views of that one tree, so they cannot disagree.

**Lane strip (below the input).** Present only when there is something besides the main conversation to show (a job running, or an agent
exists). One row per runner, indented by depth, text only: `reviewer  running  reading Sources/…  1m 12s`, then its children beneath it.
It takes rows from the transcript as the runner list and pickers do, capped, with `… N more`. **Jobs appear in it too**, which is the first
useful version and needs no subagent: it replaces ADR-0066's list above the status line, which stays reachable as `/tasks`.

**Focus.** Focus is a property of *where the input sends and what the transcript shows*:

- Default focus is **main**. A focused lane shows its own transcript in the main area and **the input sends to it** (steering at a safe
  boundary, or a follow-up if it is busy, exactly as for the main conversation). The route is always visible in text: the status line
  carries `main › reviewer › explorer`, and the prompt label names the target. Nothing is sent to a lane without it being shown.
- Keys (no Option or Command): **Down from an empty one-line draft** moves a selection into the strip; Up and Down move through it
  (a tree: Right expands, Left collapses); **Enter focuses** the lane; **Esc returns** to main; `/agents` lists and `/agents NAME` focuses.
  Every click has this key: a click on a row focuses it, a click on `main` returns.
- **Approvals follow the lane.** A subagent's approval question is the user's question. It surfaces wherever focus is (never silently
  waiting in an unfocused lane): the strip row says `waiting for approval`, the status line counts it, and answering is the same `y`, `a`, `n`
  as today, with the lane's name in the question. This is the part most likely to be wrong in a first version, so it gets a probe of its own.

**Sidebar (workbench layout).** The same tree, always visible, in the layout ADR-0046 and roadmap 0015 already name *workbench*
("a sidebar of tasks, agents and context"). A tree with the same keys and clicks (focus, expand and collapse), a divider that is also the
scrollbar track, in text first. **It is built for the character layout first**: 0015 makes the character layout first-class, so the sidebar
does not wait for pixel work (0014's chrome-cost measurement, 0003's capability probing). Pixel strokes come later and change only the divider.

**What this does not decide:** the width, whether the sidebar opens by itself when an agent appears, and what "context" lists (files read?
skills loaded?). Those are the owner's.

## Subagents, off by default (roadmap 0063)

**Off means absent, not hidden.** With `agents.enabled` false (the default): no `agent` tool in the request (no prompt cost, and the model
cannot try), no `@agent` in the picker, no lane strip or sidebar rows for agents, and `/agents` says it is off and how to turn it on. The
setting is **user-level only**: a project's configuration may turn it off and cannot turn it on, because a repository should not be able to
make your session spend tokens on its own behalf (ADR-0032's "narrow, never widen").

**Proposed rules once on**

1. **A child is an in-process agent loop** with its own context, a short task from the parent, and a **result that returns to the parent as an
   ordinary tool result**. The parent's session is therefore unchanged in shape and resumes as before.
2. **A child's transcript is its own file**, `sessions/<parent>/agents/<id>.jsonl`, linked to the parent by id, so the closed `SessionPayload`
   does not change and the lane's history survives a resume.
3. **Authority never widens.** A child gets the parent's sandbox policy or a narrower one and a **read-only tool set by default**; a write
   tool needs `agents.allowWrites`. Approvals go to the user (above). A child cannot widen anything, as no tool can (ADR-0054); a request to widen is put to the user (ADR-0055).
4. **Bounded.** `agents.maxDepth` (default **1**: a subagent cannot start one), `agents.maxConcurrent`, a turn limit and a token limit per child,
   and cancelling the parent or the lane stops the child and its descendants. Nesting beyond 1 is allowed by raising the depth, which is
   what the tree views are for.
5. **A child's output is data to the parent**, labelled by origin, never instruction: the same rule ADR-0048 states for any agent message.
6. **The model of a child** may differ (a cheaper one) through `agents.model`; unset means the parent's.

**Not decided, and each needs an ADR before code:** where child sessions live if the parent is forked or compacted; what a child may
see of the parent's context (nothing but its task is the safe default); `@agent` definitions (named, with their own prompt and tools, as in
`.agents/agents/*.md`) versus only the anonymous `agent` tool; and **addressing a session that is not a child** (ADR-0048's transport
question), which this does not need and does not settle.

## Order

1. **0061 Skills**, in phases: discovery and `ask skills`; advertisement and the `skill` tool; `/skill:` and the picker; project trust.
2. **0062 Runner tree and lane strip, with jobs only.** Useful on its own, verifiable now (jobs are real), and it is the whole UI subagents need.
3. **0062 Sidebar** (workbench, character layout).
4. **0063 Subagents**, off by default, after its ADRs; the lane focus and approval routing are built and probed here with real children.

## Questions for the owner

0. **Which harness locations are on by default?** Everything in the table except `bundled` (proposed). Should `bundled` (the `agy` built-ins, VS Code extension and plugin-cache skills) be a source the model can ask for with `from`, or only a user setting? Should the model's `from` be able to name a *directory*? (Proposed: no, only the user's own configuration or command line can.)
1. **Skills.** Load by a `skill` tool (proposed) or by the model reading `SKILL.md`? Ignore `allowed-tools` (proposed)? Is a cap on advertised skills right, and what should it default to (the owner's 26
   cost about 2,850 tokens)?
2. **Lane focus keys.** Down from an empty draft, Enter, Esc, and `/agents` (proposed). Anything that collides with how you already work?
3. **Subagent defaults.** Read-only children, depth 1, `agents.enabled` user-level only: acceptable?
4. **Sidebar.** Open by default in workbench, or only when something is running? Width?
5. **Child sessions as separate files** (proposed) or recorded inside the parent?
6. **Models in other providers.** A child's model preference that names another provider: refuse unless that connection is configured and `agents.allowOtherProviders` is on (proposed), or follow it whenever the credentials exist?
7. **Hints in comments.** The owner's agent files carry `# fallback_models: …` as a comment. Read it as a fallback list (proposed, because it is the owner's own convention), or treat comments as comments?
