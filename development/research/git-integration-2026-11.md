# Git in the screen and `#` references (roadmap 0186), 2026-11-01

What ask could show of the workspace's git state, where each piece comes from and what it costs, and how `#` resolves. Measured on
this machine (git 2.56.0); nothing here is built yet.

## What the workspace's state costs to read

One call answers everything the status line could want: `git status --porcelain=v2 --branch` gives the commit, the branch, its
upstream, ahead/behind, and one line per changed, staged or untracked file.

| Repository | Files tracked | Wall time, 3 runs |
|---|---:|---|
| ask | 2,364 | 0.01, 0.00, 0.00 s |
| aemi | 533 | 0.00, 0.00, 0.00 s |

- In a repository of 100,000 files or more it costs tens to hundreds of milliseconds, so it never runs on the input path: off the
  main actor, after the first frame (cold start 50 ms), and again only when something changed.
- "Something changed": `.git/HEAD`, `.git/index` and the branch's ref, watched with the file watcher 0127 already has (AemiIO), plus
  once after each tool call that ran a command (a command is the usual way the tree changes). No timer.
- No system API reads a repository; `git` is a subprocess, which ADR-0101 allows when no API exists. It joins the subprocess inventory,
  runs with the PATH alone, `GIT_OPTIONAL_LOCKS=0` so it never takes the index lock from a command the person or the model runs, and
  inside the sandbox's read rules (the workspace is readable already).
- ask's own `main` has no upstream configured (`branch.upstream` absent): ahead/behind is shown only when there is one.

## What the screen would show

A status line segment, fitted like the others (0074: whole, shorter, or gone): `main ↑2 ↓1 · 3 changed`, shorter `main ·3`, gone on a
narrow screen. Nothing when the workspace is not a repository. The pull request of the branch, when one is known (below), as
`#123` after the branch, clickable to open it.

## The forge: pull requests, issues, checks

Everything beyond the local repository comes from the forge (GitHub here), parsed from the `origin` remote's URL.

- Unauthenticated REST reads work for public repositories, at 60 requests an hour per address: enough for the branch's pull request
  looked up once per branch change, and a `#123` resolved when it is sent, not more.
- Private repositories need a token. ask stores none today. Options: a `github` credential kept like the providers' keys (keychain,
  0110), or a token read from the environment. Not `gh`'s: on this machine `gh` holds the owner's work account, which must not act on
  personal repositories, and reading another tool's credentials is what 0072 keeps ask from doing.
- Reads only. Writing (a comment, a review) is not in this item.

## `#` references

`#` is a third sigil beside `/` and `@` (0048), at the start of a word only, as 0185's `/` is.

| Typed | Is | The model gets | Source |
|---|---|---|---|
| `#t3` | a task | its line and description, attached after the message | the task list (0179) |
| `#i2` | an idea | its text, whole | the ideas (0180) |
| `#123` | a pull request or an issue | its title, state and body, cut to a few thousand characters | the forge |

- Attached as a skill is (0185): the text the model reads keeps `#t3` where it was typed, and each reference's content follows the
  message once, in order. `SkillInvocation.shown` already cuts at the first attachment, so every view shows the typed line.
- A picker opens at `#`: tasks and ideas first (they are local and instant), then the forge's open pull requests and issues once
  listed. An unknown reference stays text, as an unknown skill does.
- Drawn as a token (0185's look) when it resolved.
- `#123` with no forge, or offline, stays text; nothing blocks the send.

## The model's side

The model can already run `git` through the shell tool, and does. A `git` tool would cost definition bytes on every request for what a
command already gives. Recommended: no git tool, and nothing sent unasked (the task list's rule, 0179). The model sees the workspace's
state when it runs `git status`, and a pull request's text when the person writes `#123`.

## Proposed order

1. `#t3` and `#i2`: local, no forge, built on 0185's attachment and token (task t4).
2. The status line segment from `git status`, watched as above.
3. The forge, public repositories first: the branch's pull request, then `#123`.
4. A token for private repositories, once the owner chooses where it comes from.

## For the owner

- The status segment: wanted, and where (before or after the model label)?
- Private repositories: a token kept by ask (keychain), from the environment, or not at all for now?
