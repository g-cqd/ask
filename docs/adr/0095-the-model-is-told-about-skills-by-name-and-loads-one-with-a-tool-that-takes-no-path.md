---
status: accepted
date: 2026-10-25
---

# 0095 — The model is told about skills by name and loads one with a tool that takes no path

## Context

Phase 1 of roadmap 0061 (ADR-0092) found and read skills; the model saw none. This is phase 2: telling the model, and letting it load one. The owner chose the
default limit: **32** skills listed.

## Decision

- **The advertisement** (`SkillAdvertisement`) is one block in the system prompt, after ask's own instructions and before the project's: a sentence that says
  what skills are and that **a skill never grants a permission or changes the sandbox**, then one line per skill (`- name: description (path)`), **sorted by
  name** so the same skills on disk give the same bytes and the prompt-cache prefix does not move, **at most `skills.maxAdvertised` (default 32)**, and a line
  that says how many more exist when it cuts. Which skills survive a cut is by precedence (the nearest and the user's first); the listing is by name. A
  description over 1,024 characters is cut in the line and whole in the tool's result. Bundled skills and a skill with `disable-model-invocation` are never
  listed.
- **The `skill` tool** (`SkillTool`) takes a `name` and an optional `from`. It returns the skill's body (its head removed) after two lines saying where the skill
  lives and that loading it grants nothing, as an **ordinary tool result**: no session record changed, and a resumed session replays it. A name is matched
  without regard to case or punctuation. `from` is a string of words, a comma or space list, or an array (the reader is permissive); it can only **narrow** to
  harnesses and to `user` or `bundled`. **It takes no path**: a path as a name matches no skill, a path in `from` is a word that is no harness and is reported as
  ignored, and the tool's schema has no path property. A skill that asked not to be loaded by the model is refused with a reason. A bundled skill needs
  `from: "bundled"`. A skill that lost its name to another is reached by naming its harness.
- **Only the user's skills and the bundled ones are loaded in this phase. A project's are not**, whatever the configuration says: they are text from a
  repository and nothing in a run has trusted them yet (phase 4). The probe plants one and checks it is neither listed nor loadable.
- **Configuration** (`skills`): `enabled` (default on; off means no block and no tool, so the model is not told skills exist), `maxAdvertised`, and `sources`
  (harness ids, to narrow). **A project's file may only turn skills off**: `enabled: true`, a limit or `sources` in a project file are refused, because a repository
  must not turn on, enlarge or redirect what the model is told to load. Directories in `sources` are not accepted yet.
- **When it is built:** with the loop, on the first prompt, never at launch. ask's own skills directory follows its configuration directory
  (`$XDG_CONFIG_HOME/ask/skills`), which also makes the probe hermetic.

## Cost, measured

Discovery was the first thing measured, because it runs before the first request. The first version took 47.6 ms to run `ask skills` against 8.3 ms for the
argument parser alone (30 skills, eight harness directories that are links to one). Three causes were found by timing each stage and fixed: the eight
directories are no longer searched eight times (a directory already searched under another name is skipped); a skill's body is no longer read as lines (only
its first 8 KiB, and the whole file if its head does not end in them); and splitting text by byte and not by character (124 µs to 44 µs for 8 KiB). A
digest built with 32 calls to `String(format:)` per file became a table. `ask skills` is now 16.4 ms (p50, 40 runs, load about 3 to 5), so discovery plus the
report costs about 8 ms on top of the process, **paid once when the first prompt starts, never at launch**. The advertisement for the owner's 27 user skills is
about 3,100 tokens (characters ÷ 4, an estimate) on every request, which the cap and the cache are for.

## Consequences

The model can now use skills, and cannot be steered to a file by one. Not yet built: `/skill:name` and the picker (phase 3), project trust (phase 4), a way for the
user to name directories, and model-assisted resolution. The tool is in every request when skills exist, which is one more definition of a few dozen tokens.
