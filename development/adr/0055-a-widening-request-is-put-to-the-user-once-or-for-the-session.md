---
status: accepted
date: 2026-10-20
---

# 0055 — A widening request is put to the user: once, for the session, or no

## Context

ADR-0054 lets a tool call narrow its own sandbox and refuses one that asks for more. ADR-0020 decided the user may grant
such a request interactively; roadmap 0019 asks for a prompt naming exactly what would be allowed, once or for the
session.

## Decision

- **Who answers.** `ToolContext` carries an optional approver. The registry asks it when a call's request goes beyond
  the run; true runs the call under what it asked for (`SandboxRequest.granted`: the network level and the roots it
  named), with every protection kept. Without an approver (`ask -p`), the call is refused, as before; the `--network`,
  `--write` and `--read` flags remain how the user widens a headless run.
- **The question** names the tool, its command or path, and every dimension asked for beyond the run:
  `bash <command> asks for network any (this run allows localhost). Allow it?  y once · a for this session · n no`.
- **Keys.** While it waits, y, a and n answer it and Esc is no; nothing else answers it or types into the prompt, so a
  stray key cannot grant anything. Ctrl-C keeps its meaning: it aborts the turn, and cancelling the call answers no.
- **For the session** means for this process: the request is remembered in memory, and a later request it contains
  (a lower network level, roots inside its roots; a write grant is not a read grant) runs without asking. Nothing is
  written to a file or the session; a new ask starts with no grants.
- **Once** is not remembered: the same request asks again.

## Probes

Unit tests: the granted policy keeps protections; coverage by grants; the registry asks, runs widened, or refuses; narrowing
never asks; the screen's keys. Real-PTY probe V: the question's wording; y runs the call (HTTP 200 under `--network
localhost`); the same request asks again; a runs it and a covered request then runs without asking; a larger request asks;
n refuses it, and the file it would have written does not exist. Probe W: Ctrl-C while the question waits aborts the turn,
the call does not run, and the editor works again. Nine compiling mutations caught (diary 52).

## Consequences

The only way past the sandbox from inside a run is a person pressing y or a. Grants are not recorded in the session, so
`--resume` and `/reload` start without them; that is deliberate. Session-wide narrowing by the model is the remaining
slice of 0019.
