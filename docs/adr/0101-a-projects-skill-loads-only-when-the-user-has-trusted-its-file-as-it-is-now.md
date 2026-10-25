---
status: accepted
date: 2026-10-25
---

# 0101 — A project's skill loads only when the user has trusted its file as it is now

## Context

A project's skill is text from a repository: its description goes into the system prompt and its body is instructions the model follows. Phases 2 and 3
(ADR-0095, ADR-0097) loaded only the user's and bundled skills for that reason. Phase 4 lets a project's skills load, on the same terms as a project's
configuration file (ADR-0032): the user looks, then trusts the bytes.

## Decision

- **Trust is for a file's path and bytes**, in the store the configuration already uses (`trusted.json`: path to SHA-256). A skill's key is its **real path**, so a
  link does not make a different file trusted. The store's format did not change; `ProjectTrust` gained `standing(of:digest:)` and `trust(_:digest:)` because a
  skill has its digest already.
- **Discovery enforces it** (`SkillDiscovery.discover(…, trust:)`), not the callers: a project skill whose file is not trusted as it is now goes to
  `catalog.untrusted` (with `unknown` or `changed`), **not** to `skills`. The parameter defaults to a store that trusts nothing, so a caller that forgets it gets no
  project skill rather than all of them. An untrusted skill is advertised to no one, is not loadable by the tool, **does not shadow** a skill of the same name (the
  user's own still loads), and does not take a file's place if the same file is the user's own, reached through a link.
- **The text is checked again when it is loaded** (`SkillContents.load` throws): a project skill's file is hashed as it is read and must equal what discovery trusted,
  because a file can change between discovery and the tool call (a `git pull`, or the model's own `write`). A user's skill is not re-checked; the user owns it.
  The digest covers the same bytes the model reads (the first 256 KiB).
- **`ask trust --skills [NAME…]`** trusts this project's skills as they are now, all or by name, and prints each with its path, a digest prefix and the start of
  its description. It refuses without a terminal on stdin, as `ask trust` does (exit 77), and is as much a speed bump as ADR-0032 said that is. **`ask untrust
  --skills [NAME…]`** takes it back. Neither changes what `ask trust` and `ask untrust` do without the flag.
- **What trust covers:** the `SKILL.md` text only. Files beside it (scripts, references) are not covered; the model may read or run them only under its own sandbox
  and approvals. The command says so each time.
- **The person is told:** `ask skills` has a section for what waits and why (`never trusted` or `changed since trusted`); the first prompt of a screen session
  shows one notice with the count (it is when skills are first looked for); `/skill:name` on a waiting skill says why and how. **The `/` picker lists a waiting skill,
  marked as not trusted**, which departs from the roadmap's "not offered by the picker": a skill that seems not to exist is worse than one that explains itself.
  The model is told nothing about them, not even their names.
- A project's configuration still may only turn skills off; `skills.sources` is the user's.

## Not covered

Print mode (`ask -p`) shows no notice about waiting skills; `ask skills` is the place. A trusted skill's other files are not covered, as above. The agent's bash tool
can still edit the store (ADR-0032's gap, which the sandbox's denial of `~/.config/ask` closes, not this); the terminal check is the same speed bump.

## Consequences

A repository can no longer put words in the system prompt through a skill without the user having run a command over the file; a changed file stops loading until they
look again. The cost is one more thing to do per project, and `git pull` that changes a skill silently drops it until then, which the notice and `ask skills` say.
