---
status: accepted
date: 2026-10-25
---

# 0092 — Skills are found in every harness's directories and read without being strict

## Context

The owner uses 26 skills daily from tools that each keep their own directory, and asked (design note, 2026-10-24) that ask's skill tool pick from
**any harness's locations unless an argument says otherwise**, and that **parsing of tools and models be as permissive as possible**. This is the
first phase of roadmap 0061: finding, reading and reporting. Nothing is yet offered to the model.

## Decision

- **Sources are a table** (`SkillSource`): `agents`, `ask`, `claude`, `codex`, `pi`, `opencode`, `vibe`, `copilot`, `agy`, each with user, project
  and bundled directories. Adding a harness is adding a row. The user-level locations (except `ask`'s) were found on the owner's machine; the
  project-level locations other than `.agents/skills` are from those tools' conventions and were found in no project there, so they are proposals.
- **Deduplication is by real path** (every symlink resolved), then by name. On the owner's machine eight harness directories are symlinks to one;
  without it every skill would be eight. A second skill of the same name is **shadowed** (reported, not offered with the first) unless its bytes are
  identical, in which case it is the same skill and nothing is said. Precedence: the nearest project directory first, then user, then bundled.
- **Bundled skills are off unless asked for** (a tool's own, changing with its updates); asking is `bundled` in the selection. A **selection** is
  words (`SkillSelection`): harness ids, `user`, `project`, `bundled`. It only narrows, keeps the words it did not understand to report them, and has
  no way to name a path, so the model's argument (phase 2) can never make the tool read anything but a known harness's skills.
- **A definition file is read, never rejected** (`DefinitionFile`). It returns fields, comment hints and diagnostics and cannot fail. It reads YAML
  heads (plain, quoted and block scalars, flow and block lists, nested maps, comments, duplicates, tabs), TOML (strings in every form, arrays over lines,
  tables), a BOM, CRLF, unterminated heads, and no head at all (the name comes from the directory and the description from the body). Keys compare by
  meaning (`allowed-tools` = `allowed_tools` = `allowedTools`). Nesting is bounded (flow 32, indentation 48) because a property test found that 50,000
  brackets overflowed the stack; work is linear because the same test found that 20,000 keys took 47 seconds with a quadratic duplicate check.
- **Comments that read as `key: value` or `key = value` are kept as hints.** The owner's files carry `# fallback_models: …` and `# tier_models = […]`
  where a harness ignores a setting another would use.
- **Tool lists are token lists** (`ToolReference`): from a list or a scalar, split outside parentheses and quotes, bullets and quotes removed,
  `Bash(git diff:*)` one token with a qualifier, wildcards and `mcp__` names kept whole. Each token is looked up in a **data table of spellings**
  (`ToolAliasTable`); a token in no row is kept, reported as unmapped, and means nothing. **A list is only ever a restriction or a note; it never adds a tool.**
- **Model preferences are word lists** (`ModelPreference`): a `model` field as a scalar or list (display names with spaces stay whole), then any
  comment hint whose key mentions models, without repeats; `inherit` or no model means the parent's. Matching words to a connection's catalog is a
  later step (roadmap 0063), and when nothing matches the parent's model is used.
- **`ask skills`** lists what was found (`--from` selects, `--verbose` shows tools, models, other fields and every directory searched) and **`ask skills
  --inspect FILE…`** shows how any file was read, skill or agent, so the reader can be checked against real files.

## Evidence

The owner's whole harness corpus, 147 files (skills, bundled skills, 84 agent definitions in six formats, 28 of them TOML), through
`ask skills --inspect`: **147 read, none rejected, none without a head, no diagnostics**. `ask skills` from the project directory found 30 skills,
one shadowed (a different `skill-creator` under `.system`), none skipped. The advertisement would cost about 3,500 tokens (characters ÷ 4, an
estimate); that figure needs a cap and a stable order, which is phase 2.

## Consequences

Unmapped tools are common and harmless: the owner's agent files name `LSP`, `WebFetch`, `TodoWrite`, `call_mcp_tool` and others ask has no tool for.
The alias table grew by the spellings those files use, and the rest are deliberately unmapped. Phases 2 to 4 (the advertisement and the `skill` tool,
`/skill:` and the picker, project trust) and model-assisted resolution are separate.
