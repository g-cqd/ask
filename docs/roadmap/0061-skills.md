---
status: not-started
blocked-by: []
date: 2026-10-24
---

# 0061 — Skills: discovered, advertised cheaply, loaded on demand, trusted by project

The owner ranks skills above subagents, and uses 26 of them daily (`~/.agents/skills`). The design, the evidence from that collection and the
open questions are in `docs/research/skills-and-agents-design-2026-10.md`; the decisions below are *proposed* there until the owner accepts them.

## What it is

The Agent Skills form: a directory with `SKILL.md`, frontmatter with `name` and `description`, optional `scripts/`, `references/`, `assets/`.
The model is told each skill's name, description and path; it loads the body only when the task calls for it; the user can force one with
`/skill:name args`. A skill **grants no permission**.

## Phases, each independently shippable

1. **Discover and report.** Find skills in **every harness's locations** (the source table in the design note: `agents`, `ask`, `claude`, `codex`,
   `pi`, `opencode`, `vibe`, `copilot`, `agy`; user-level and project-level; bundled and plugin-cache directories only as the off-by-default
   `bundled` source), **deduplicated by real path** (the owner's machine has eight of them as symlinks to one directory) and then by name;
   parse them **permissively** (below); and show them: `ask skills` and `/skills` list name, source, trusted or not, diagnostics, unmapped tool
   tokens, and the estimated tokens the advertisement costs. No model-visible change yet.
2. **Advertise and load.** Name, description and path in the system prompt, sorted by name (a stable cache prefix), capped with a visible
   "N not shown"; a `skill` tool that returns the body and says where the skill lives. The result is an ordinary tool result: no change to
   `SessionPayload`. The tool picks from **every enabled source unless narrowed by an argument**: `from` takes a source id or a list of them
   (`"codex"`, `["claude", "agents"]`) or `"user"` / `"project"`; the model's `from` can only narrow and cannot name a path. The same narrowing
   is available to the user as `ask --skills-from`, `skills.sources` (which may also name directories) and `/skill:name --from claude`.
3. **Ask for one.** `/skill:name args`, and skills in the `/` picker with `SKILL` and `PROJECT` labels; a built-in wins a name collision;
   `disable-model-invocation: true` hides a skill from the advertisement and keeps it reachable.
4. **Trust.** Project skills load only for a trusted project (ADR-0032's mechanism, extended to the set of `SKILL.md` files by name and
   SHA-256); a changed skill is untrusted until looked at again; a project's configuration may turn skills off and never on.

## Parsing: as permissive as possible (the contract is in the design note)

The reader never fails: it returns fields and diagnostics, and skips a file only when no name and description can be derived. It accepts a BOM,
CRLF, `---` or `+++` fences, TOML, no frontmatter at all (name from the directory, description from the first heading or paragraph), any
case of `SKILL.md`, plain, quoted and block scalars, flow and block lists, nested maps, comments, duplicate keys, and keys spelled
`allowed-tools`, `allowed_tools` or `allowedTools`. **Tool lists** (`tools`, `allowed-tools`, `disallowedTools`) are an ordered token list from a
list or a scalar, split outside parentheses, mapped through a data table of tool-name spellings, with unknown tokens kept and reported and never
an error; a list is only ever a restriction or a note and **never widens**. **Models** are an ordered preference list (aliases, display names,
ids, provider-qualified forms, a `fallback_models` hint) resolved against the active connection's catalog, falling back to the parent's model
with a notice, never failing and never leaving the connection on its own. Shapes and counts are from the owner's 147 real files.

## Rules that must hold, each with a failing test first

- A skill grants nothing: loading one changes no sandbox policy and approves no tool; `allowed-tools` is parsed, shown, and ignored.
- An untrusted or changed project skill is not advertised, not loadable by the tool, and not offered by the picker, and `ask skills` says why.
- Two skills with one name: the first by precedence loads, the other is reported, never both.
- The same skill reached through two paths (a symlink, or `~/.claude/skills` pointing at `~/.agents/skills`) is one skill.
- The advertisement is byte-identical between two requests with no change on disk (a cache prefix that does not move), and over the cap
  it states how many are omitted.
- Quoted values, folded scalars and multi-line descriptions parse; a malformed skill is a listed diagnostic, never a startup failure.
- The parser cannot fail: a property test over arbitrary bytes and truncations of every shape in the corpus finds no trap and no hang, and a
  second run gives the same result; each shape the corpus has (comma string, flow list, block list, harness-specific tool names, an alias with
  a trailing `# fallback_models:` comment, display-name lists, TOML, no frontmatter, a quoted name) has a fixture.
- An unknown tool token is kept and reported and grants nothing; `Bash(git diff:*)` stays one token; a list that maps to nothing changes nothing.
- A model preference resolves to the first match on the active connection, by alias, display name or id; with no match the parent's model is used
  and a notice names the token; a token naming another provider is not followed.
- With no `from`, a skill is found in any enabled source; with `from`, only there; the model's `from` cannot name a path.
- Eight symlinked harness directories to one real directory yield each skill once.
- The `skill` tool refuses a name that is not an advertised or trusted skill, and returns nothing outside the skill's own directory.
- `/reload` picks up a changed skill without a restart; a resumed session replays an earlier skill load unchanged.

## Probes (real, before each phase is called done)

- **Every skill and agent file reachable from the owner's harness directories parses with zero rejected** (147 files, 28 of them TOML); the name
  mismatch in `openai-docs` (a quoted name) is accepted; the advertisement's size is measured with a
  real tokenizer count where one exists, and reported as an estimate where not.
- Under `read: 'workspace'`, a skill in `~/.agents/skills` still loads through the tool, and its `references/` file is readable only
  because the skill was enabled, not because the policy was widened.
- A real-binary PTY probe types `/skill:name`, sees the picker label, runs it against a fake provider, and checks the exact request.
- Prompt-cache evidence: two requests with unchanged skills share a prefix; adding a skill changes only what it must.

## Done when

All four phases are built, each rule above has a test that failed before its code, the probes above pass against the release binary, the cost
of the advertisement is measured and capped by default, and the owner's questions in the design note are answered or have a recorded default.

## Not in this entry

Skills that run code on their own (a skill's scripts run through `bash` under the sandbox like anything else), a package manager for skills,
and subagents (0063).
