---
status: accepted
date: 2026-10-25
---

# 0103 — A trusted project file may name an MCP server, and trusting says what would start

## Context

ADR-0099 let only the user's own file name a server, because naming one runs a program and a repository must not start one. That is the
right default and a poor ceiling: a team that shares a project's servers has to put the same lines in everyone's own file. The
project's file already has a gate that the user's does not need: it is ignored until a person at a terminal runs `ask trust`, a later
change untrusts it, and the agent cannot run the command (it needs a terminal). What was missing is that the trust said nothing
about what it would let happen.

## Decision

1. **A project's `mcp` section is read once the file is trusted**, as the other keys are, and layers over the user's by server name
   (a project's server replaces a user's of the same name, whole).
2. **Trusting says what it would start.** `ask trust` prints, after the keys the file sets, a line for each server: the program and its
   arguments, or the address without its query, fragment or credentials, and "(off)" for one switched off. It never prints an environment
   value or a header. The heading says the servers run outside ask's sandbox.
3. **A project's file may not read ask's environment into a server.** `${NAME}` in a project's `env` or `headers` is refused, when the
   file is loaded and so when it is trusted. In the user's own file it is how a token stays out of the file; in a repository's it would
   carry a key from the user's environment to a server the repository chose. An opening `${` with no closing `}` is text, as in the user's
   file.
4. **Nothing else about a server differs.** Its process gets the same minimal environment, the same watchdog, the same refusal of a
   narrowed session.

This supersedes point 2 of ADR-0099 and nothing else.

## Consequences

A trusted project can start programs, which is what trusting a project that names them means, and the person is told the programs
before they agree. The existing protections hold: an untrusted or changed file is ignored; a prompt-injected model cannot run `ask trust`
(it needs a terminal; the speed bump is as strong as ADR-0035 says and no stronger). A person who trusts without reading is as exposed as
with any other agent's project servers; the lines are there to be read.

## Probes

| Claim | Result |
|---|---|
| An untrusted project's server is not started | `Scripts/probe-mcp.py` D: the run says the file is ignored and the marker the server's command would write does not exist |
| Trusting says what would start and shows no value | probe D through a terminal: "proj: runs sh -c …" and the sandbox note; the environment value in the file is not in the output |
| A trusted project's server starts and its tools are offered | probe D: the marker exists and the first request carries `mcp__proj__echo` |
| A project's `${NAME}` is refused when trusting | probe D: `ask trust` fails and names the reason |
| Tests | 15 in the configuration suite (5 new for this, one replaced: a project may name a server, `${NAME}` refused in `env` and in `headers`, literals and an unterminated opener allowed, the consent lines and what they leave out, an empty section); compiling mutants all caught: the check inverted, headers not checked, env not checked, an unterminated opener counted, a query shown, arguments hidden, "(off)" not said |
