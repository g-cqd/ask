---
status: accepted
date: 2026-10-26
---

# 0119 — Details are for when they are asked, and a notice is for acting

## Context

A session opened with up to nine lines the person had not asked for: the session resumed, the build reloaded, the destination a resume pinned, the sandbox off and then in force, the thinking effort, a new build appearing. All of them were true and none
of them was needed to read the conversation; the label already said the model, the status line already said the sandbox was off, and `/config` says the rest.

## Decision

Every line ask says on its own account is one of two kinds.

- **A notice** is something the person may need to act on or that changed what will happen: an error, a warning, a file that was ignored, a catalog that could not be used, a credential that could not be saved, a
  compaction, a retry, a repaired context, the result of a command they ran, Apple's model chosen because nothing is signed in. Always shown.
- **A detail** is what ask decided or found by itself and the screen already shows or `/config` can: shown with `--verbose` (`-v`), or after `/verbose`, which also shows the ones held back (the latest 50). In `-p` they go to standard error only with `--verbose`.

Classified as details: the session resumed, the build reloaded, a new build appearing, the destination a resume pinned, the sandbox off (`--no-sandbox` is in the status line) and the sandbox in force, the thinking effort and its status, which configuration files
applied, the instruction files read, which provider was chosen for lack of a flag and which model a name stood for, `Configuration reloaded` and what changed, that a response was continued at its output limit.

Not changed: `ask: tokens …` and `ask: session …` at the end of `-p` (standard error, scripts read them), and everything that is the answer to a command.

## Evidence

`VerboseControllerTests` (4): not shown by default, shown with verbose, `/verbose` replays what was held in order and hides again, only the latest 50 are held. Real binary, `-p`: quiet prints the answer and the two closing lines; `-v` adds the provider, model, sandbox and thinking lines.

## Consequences

A person who relied on seeing the sandbox line at startup now sees it with `-v`; the status line still names `no sandbox` in both. The classification is a list in this ADR and the code (`RunSettings.details`, `ConversationUpdate.detail`), so a new line has to choose.
