---
status: accepted
date: 2026-11-15
---

# 0156 — Codemode: a script calls the tools, run by JavaScriptCore in a helper process of ask

## Context

ADR-0123 shelved codemode (roadmap 0012) "until real use shows many-step tool sequences that cost too many round trips". On
2026-11-15 the owner put it first, "inspired by pi's integration": one script instead of many calls, run in parallel and in
chains, its noise filtered before a compact result goes back to the model; in JavaScript (JavaScriptCore, bun or node) and in
Python. `development/research/codemode-2026-11-15.md` has what pi does (read, and run on edge cases) and what each way of running
a script costs on this machine. Five decisions were put to the owner with those numbers.

## Decision

The owner's, 2026-11-15:

1. **JavaScriptCore, in a helper process.** ask starts itself as a child that hosts the VM, as it does for the GitHub read
   (ADR-0152). The child is killed at its deadline or past its memory, so no call outside Apple's public headers is needed,
   and a script that brings the VM down does not bring ask down.
2. **A script's only capability is the tools**, as in pi: no files, network, timers or programs of its own. Every read,
   write and command a script makes is a tool call.
3. **A script is approved once, as a whole.** The person is shown the script before it runs; its calls then run without
   further questions, still inside the sandbox.
4. **Python waits with `asyncio`** (`await tools.read(...)`, `asyncio.gather`), and **runs on the default Python
   runtime**: the system's `python3`, with nothing to install.
5. **On by default, one tool.** Only the JavaScriptCore surface is served for now; Python follows, and the tool then takes a
   language.

## What follows from them

**The surface, copied from pi on purpose**, since each of these is something a person or a model can feel: the script is
the body of an async function (top-level `await` and `return`); `tools.<name>(args)` returns a promise of the tool's text,
and rejects with an `Error` carrying the tool's words when the call fails; `text(value)`, `console.*` and a top-level
`return` are the output; `exit()` ends it; `ALL_TOOLS` lists what can be called; a first line
`// @options: {"max_output_tokens": …, "timeout_ms": …}` sets the script's own limits. Calls made before a failure are not
undone; a call still running when the script ends is cancelled. The result starts `Script completed` or `Script failed`
with the wall time; several text items are each headed `==> text N/M <==`; console lines follow in one `<console_output>`.

**The limits are the design** (roadmap 0012), each a red test, each a failure that says why, never a silent cut:

| Limit | Number | From |
|---|---|---|
| Deadline | 120 s unless the script names one, 600 s at most | what `bash` allows a command |
| Memory of the child | 256 MiB, then it is killed | pi |
| Output held | 16 Mi characters, 100,000 items, then the script fails | pi |
| Output returned | 10,000 tokens unless the script names fewer or more; past it the start and the end, the whole in a file | pi; ask's own output cap |
| Calls in flight | 16 a script; more wait their turn | new: roadmap 0012's "cap on concurrent workers" |
| Scripts at once | 2 children a process; more wait | pi |
| A promise nothing can settle | fails at once | pi; JavaScriptCore does not notice, so the host counts what it owes |

**A nested call is a tool call of the loop's**, not a side door: it passes the loop's hooks (a hook that blocks a command
blocks it inside a script too) and the sandbox. What the script's approval replaces is the question to the person: a nested
call that the policy would ask about runs; one that asks for more than the sandbox allows is refused, since nobody widens the
sandbox in the middle of a script. The loop gives a tool the means to call the others (`ToolContext`), so the codemode tool
holds no registry of its own, and it cannot call itself.

**The approval** is one question about the `codemode` call, with the script as its detail and the tools it names in its
words. `--yes`, `approvals.allow` and an answer for the session cover it as they cover any tool. `ask -p` has no gate: its
command line is the consent, as for every tool.

**The parts.** `AskCodemode`, a library below the tools: the VM's host (JavaScriptCore, the prelude, the script's end of the
bridge) and the bridge's messages. The hidden `ask codemode` runs it. `AskTools` has the tool and the child's keeper: it
starts the child through the stdio transport the MCP client already has (one JSON-RPC message a line, a process group, a
grace before the signals), serves the script's calls, and enforces the limits. Nothing new speaks JSON-RPC.

**Direct tools stay declared beside it** (pi's `on`): the model already has each tool's schema, so the codemode
description says how a script calls them and repeats none. `codemode` in the configuration turns it `"off"`.

## Consequences

- ADR-0123's third point (codemode waits) is replaced by this record; its first two stand.
- A script costs a process: ask's own start, measured before it is built on (the order of work's first step can fail there).
- The session records the `codemode` call and its result. The calls a script made are in neither the session nor the
  context: that is the saving, and it means a resumed session cannot show them.
- JavaScriptCore is linked into ask. Measured: nothing at idle (5.6 MB resident, as Foundation alone), 3 MB for a live VM,
  which lives in the child.

## Not built first, and said so

- **Python.** A child `python3` under a deny-everything profile that allows the interpreter and its library alone, on the
  same bridge. `import asyncio` is 40 ms of each script's start (55 ms against 21), accepted with the owner's choice.
- **Hiding the direct tools behind codemode** (pi's `only`): it needs the tools declared inside the description, within a
  budget, which is a renderer ask does not have.
- **pi's `image()`, `store()`/`load()`, `searchTools()`, `models`.**
- **A profile around the JavaScriptCore child.** The VM has no way out but the tools; a profile would be a second wall, for
  9 ms a script.

## Open, for the owner when the first version runs

- Whether a script may call `question` and `agent`. First version: every tool but `codemode`.
- Whether the approval should wait until a script's first call that would have asked, so that a script that only reads is
  never asked about. As decided, every script is asked about once, unless an answer or a setting covers it.

## The order of work

1. A spike that can fail: `ask codemode` hosts JavaScriptCore and answers one script with one call, under the strict flags;
   its start is measured.
2. The host: the prelude and the script's semantics, tested in process.
3. The keeper: the child, the bridge, each limit as a red test.
4. The loop: a tool's means to call the others, through the hooks; the approval as a whole.
5. The tool: its description, the result's format, the setting, the user guide, the screen's block.
6. `Scripts/probe-codemode.py`: a model's script through the real binary; then the budgets.
7. Python.

## Probes

`development/research/codemode-2026-11-15.md` and diary 2026-11-15-17.

## Amendment (2026-11-16): the open points, settled

The owner's answers, asked with the first version running:

1. **Python runs on the first `python3` on the `PATH`.** Not the system's `/usr/bin/python3`, which is Xcode's shim (158 ms to
   start with asyncio, against 55).
2. **A script may call neither `question` nor `agent`**: "makes no sense for now". Every other tool but `codemode` itself.
3. **A script is asked about once, whatever it calls, unless `--yes` or `--yolo` is on.** The question is not put off until a
   script's first call that would have asked. An answer for the session and `approvals.allow` cover later scripts, as before.

Both lists under "Open, for the owner" above are closed by this.

## Amendment (2026-11-16): the output limits, and Python as built

**A script may say 1 Mi characters in 10,000 items**, not pi's 16 Mi and 100,000 as the table above has it. A script's result
crosses to its keeper as one line, and the connection takes lines of 8 MiB: a result past that was dropped, and the script
waited out its deadline (diary 2026-11-16-02). The new numbers fit at their worst, six bytes a character on the wire. What the
model is returned is unchanged: 10,000 tokens by default, the whole in a file.

**Python** runs on the first `python3` of the `PATH`, as it really is on disk, with `-I -S` (no variable, no user site, no
installed package), under a profile of its own whatever the session's sandbox is: everything denied, then its interpreter and
the system's libraries readable. Its memory is watched from inside (`setrlimit` is not enforced on macOS). The tool describes
Python, and takes `language`, only where there is one.

## Amendment (2026-11-16): what a script says crosses as it is said

A script's output no longer crosses as one line when it ends. Each thing it says is a `said` notification to its keeper, as it
is said, and `run` is answered with how the script ended. A script stopped at its deadline or at its memory therefore keeps
what it had said until then, and its failure says so no longer by "What it had said is lost." (diary 2026-11-16-03). The 8 MiB
of a line bounds one thing said; the megabyte and the 10,000 items stay, held by the script's process and checked again by the
keeper, which stops a process that says more.
