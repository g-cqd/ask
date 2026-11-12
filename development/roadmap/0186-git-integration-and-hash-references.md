---
status: in-progress
blocked-by: []
date: 2026-11-01
---

# 0186 — A git integration: the workspace's state in the screen and for the model, and `#` for pull requests, issues and tasks

Owner (2026-11-01): a git integration that polls, from the workspace's git setup, the information worth showing in the screen and
passing to the model; and `#` designating pull requests, issues or tasks.

## Owner (2026-11-01): `#` for tasks and ideas too

`@` stays for files. Tasks and ideas are pointed at with this item's sigil, `#t3` and `#i2`, beside `#123` for a pull request or an
issue; the model gets the task's or idea's text attached, as a skill's is (0185). This replaces the `@task` and `@idea` of 0179 and
0180.

## Still owed

- A research note first: what to show (branch, ahead/behind, dirty files, the current pull request and its checks), where it comes from
  (git itself; a forge's API through `gh`-like credentials, which ask must not borrow from another tool's keychain entries; MCP servers
  that already speak to forges), how often to poll without costing idle memory or the cold start (50 ms), and what the sandbox allows.
- The model's side: what it is told, and when (a line in the context, or a tool it calls, as the task list is: 0179).
- `#` in the input grammar (0048): a third sigil, for things that are tracked: `#123` a pull request or issue, `#t5` a task (0179).
  Decide the forms with the owner, and keep `#` inside a word, and a Markdown heading at a line's start, as text.

## Research (2026-11-01)

`development/research/git-integration-2026-11.md`: `git status --porcelain=v2 --branch` answers the whole status in one call (about
10 ms on ask), refreshed when `.git/HEAD`, the index or the branch's ref changes and after a command runs, never on the input path; the
forge read-only, unauthenticated for public repositories, never through `gh`; `#t3`, `#i2` and `#123` attached as skills are; no git
tool for the model. Proposed order: `#t3` and `#i2` first (local), then the status segment, then the forge. Two questions for the
owner in the note.

## Done (2026-11-01): `#t3` and `#i2`

- Sending: `ListReferences.attach` puts each named task (its line and description) and idea (its text) after the message, once, in the
  order named, after any skill; only the typed line is read, a `#` inside a word or an id that is not there is left as text.
  `SkillInvocation.shown` cuts at the first skill, task or idea, so every view shows the typed line. The screen's turns and print runs
  both attach.
- The picker: a `#` that starts a word lists the open tasks and ideas (the conversation's `#` choices, asked for once and again after a
  turn, as command lists are); choosing one replaces the word. A known one is drawn as a token, as a skill is (0185's look).
- Tests: `ListReferencesTests`, `ReferencePickerTests`; 7 mutants, six killed, the seventh a redundant guard, removed.
- Still owed: `#123` (the forge), and the status segment, in the research note's order.

## Owner (2026-11-12)

- The status segment: wanted, at the end of the status bar.
- Private repositories: a token from the environment (`GITHUB_TOKEN`), never `gh`'s.
