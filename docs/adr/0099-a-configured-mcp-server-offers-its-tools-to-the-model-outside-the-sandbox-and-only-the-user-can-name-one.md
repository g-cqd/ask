---
status: accepted
date: 2026-10-25
---

# 0099 — A configured MCP server offers its tools to the model outside the sandbox, and only the user can name one

## Context

ADR-0096 built the client and its two transports and registered nothing. The pieces that remained are the ones with consequences: who may
name a server (naming one runs a program), what the model sees (a real suite has 207 tools, about 689 KB of schemas), what a server is
trusted with (it is third-party code, outside ask's sandbox by nature), and when it starts (seconds, against a start budgeted in
milliseconds). Roadmap 0067 phases 3 and 4.

## Decision

1. **Servers are named under `mcp` in the user's own config file**, one object a server: `command`, `args`, `env`, `cwd` for a process;
   `url`, `headers` for a web service; `tools` to choose; `enabled: false` to keep one without starting it. A name is 1–32 letters,
   digits, `-` and `_`, no `__`, because it becomes part of the tool's name. A server is exactly one of a process and a URL, and keys
   that belong to the other kind are refused, not ignored. `${NAME}` in `env` and `headers` is filled from ask's environment when the
   server starts (an unset one fails that server and names the variable), so a token need not be written in a file. `ask config` shows
   the servers and how they are reached, never what they were given.
2. **A project's file may not name a server**, trusted or not: `ask trust` parses it as a project's and refuses (probed), so a repository
   cannot get a program started by being trusted. Allowing it behind trust is a later decision (roadmap 0067).
3. **Tools are offered as `mcp__<server>__<tool>`** (ADR-0092 keeps these whole), after the built-in tools, in the order the servers
   and the tools were listed, so the prompt-cache prefix does not move. A name outside what providers accept is sanitised and takes a
   hash of the original, so it is the same every time and two tools never share one. A server's tool cannot take a built-in's name.
4. **A server with more than 16 tools and no `tools` list offers none**, and says so, naming the key. Sixteen is a default
   (`MCPHost.defaultMaximumDirectTools`), not a measurement; the cost it prevents is measured (ADR-0096). A `tools` list lets any server
   in. A search tool in front of a large server is the alternative and is not built.
5. **Servers connect in the background.** The interactive screen starts them at launch, so they are connecting while the person types and
   the first prompt usually has their tools; one that is late is offered from the next request. A one-shot `-p` run waits for them and
   prints what did not start on stderr, since it has no later turn. A server that fails costs only itself, with the transport's reason
   (for a program, why it could not be launched, or the last line it wrote to standard error).
6. **Servers outlive the loop.** The loop is rebuilt whenever the configuration changes; the hub keeps the servers, applies a changed
   configuration at the next prompt, and starts or stops only what changed. A server whose tools change is listed again.
7. **A server runs outside ask's sandbox, and says so to the model's face.** Its process gets only a minimal environment (ADR-0096), but
   what it does is its own. So its tools are refused when this session's sandbox has been narrowed below the run's (by `narrow_sandbox`),
   because that narrowing is a promise a server cannot keep. A `sandbox` argument of a server's tool is the tool's own argument and is
   never read as a request to narrow ask's. **Limit, stated plainly:** when the run itself was started under a strict policy, the
   servers are still offered, since the user named them; refusing there would refuse them always, because the default policy is already
   restricted.
8. **What the model reads of a result is text.** Text blocks are joined; an image or sound is named with its type and size, never pasted;
   a resource gives its text; structured content stands in only when there is no text. `isError` is an error output. Every result goes
   through the registry's output cap like any tool's.
9. **The screen says what happens.** A notice when a server connects (how many of its tools are offered), is skipped, fails or goes
   away, and `/mcp` lists each server's state with notes (for instance a tool named in `tools` that the server does not have).

## Consequences

The model can use any tool a configured server offers, with no per-call approval: naming the server is the consent, as in the other
agents. A server still running when ask is killed by a signal is told only by its input closing, which a stubborn server ignores (the
normal exits stop every server, with the grace of ADR-0096). The configuration is read again before each prompt, so a change applies at
the next one, not at once. `Sources/ask` has no tests (roadmap 0028); what is wired there is covered by the two probes below.

## Probes

| Claim | Result |
|---|---|
| A configured stdio server's tools are offered, a call reaches it, its text returns | `Scripts/probe-mcp.py` A through the real binary and a fake provider; an older binary does not offer the tool (the control) |
| The server does not get ask's API key | The fixture's `env` tool, called through the model: `PATH` and `HOME` present, nothing of the key |
| The server's process is gone when ask is | The process id the server wrote is not alive after the run |
| More tools than the limit offers none and says how to choose | probe B: 20 tools, none offered, stderr names `mcp.many.tools` |
| A server that cannot start costs only itself | probe C: the run answers, stderr names the server and why |
| A project's file cannot name a server | probe D: untrusted it is not read; `ask trust` refuses it and says why; the server is never started |
| The screen announces servers and `/mcp` lists them | `Scripts/probe-mcp-screen.py`: both notices with no key typed, the listing, `/help`, and the first request already carrying the tools; an older binary does not know `/mcp` |
| The raw screen after two notices looks corrupted | **Refuted as an app bug**: pyte does not do scroll regions, so only a repaint is a faithful picture (the harness says so); the probe reads raw bytes to wait and a repaint to look |
| Nothing is spent when nothing is configured | cold start p50 12.79 ms against 12.47 ms for the build before (40 interleaved runs each, interquartile ranges 12.4–13.0 and 12.3–12.8), budgets all within: idle memory 9.6 MiB of 24, input 0.21 ms of 2, action 1.96 ms of 5; the binary grew from 12.18 to 12.80 MB, partly other work merged since |

## Tests

71 new: 52 in `AskToolsTests`, and 19 in `AskAgentCoreTests` (8 for the live registry, 11 for the configuration), plus the client's 80 (ADR-0096): the registry with live tools
(names, order, a built-in's name kept, caps, a foreign `sandbox` argument, a narrowed session), the configuration section (kinds, names,
layering, project refusal, the description hiding secrets), names, results, `${NAME}`, the host (connecting, listing, limits, failures,
going away, changing, stopping while starting), the hub (the same servers not restarted, changes, notices, stopping), the report and the
standard transports. Compiling mutants, all caught: limit off by one, list ignored, tools staying when a server goes, a stop announced
as a failure, variables not expanded, changes ignored, a failed server left running, the narrowing check removed, `isError` ignored,
a weak name hash, the project refusal removed, double underscore allowed, both kinds allowed, any URL scheme, the old servers not
stopped, notices not forwarded. Three survivors were equivalent or redundant and the code was removed instead (duplicate-name filter,
a second removal of a stopped server's tools, an empty-hub shortcut that changes nothing observable).
