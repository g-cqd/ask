---
status: in-progress
blocked-by: 
date: 2026-10-18
---

# 0009 — The agent loop

The centre of the project. Everything so far is scaffolding around a program that prompts and reads
bytes.

## The loop

A submitted message joins the active branch. Build a model request from the system prompt, the active
branch, the available tools and the model settings. Send it through the provider. The provider streams a
response that may contain text and tool calls. Record the response, execute each tool call, record the
results — that is one turn. If tool results or queued messages require another request, start another
turn. Otherwise the run ends.

## Acceptance is not "it runs"

This entry is **not done** until the action-to-action budget is re-derived against a real action, and
`0007` has landed. A loop that runs but leaves `Budget` measuring Enter producing a prompt in a program
with no agent has made the project's headline claim *less* true, not more.

## Steering and abort

Worth designing in from the start, because retrofitting them is how agent loops become uninterruptible:

- **Steering** messages enter after the current assistant turn.
- **Follow-ups** enter after the agent finishes its pending work.
- **Abort** stops the current run and returns queued messages to the editor.

All three need the render loop to stay responsive while a turn is in flight, which is an input-architecture
decision, not a later patch.

## Where it lives

`AskAgent`, per the manifest's own declared layout — kept separate from `AskTUI` so the loop is testable
without a terminal, and so `ask` the binary links only what it uses.

## Done when

The loop runs end to end against a real provider, a tool executes and its result reaches the model, abort
works, and `0007` has re-derived the budget.

## Reordered (ADR-0019)

Next, and headless first, driving `ask -p` with tools. `0008`'s remaining items (placement, a second writer) are decided here. It lives in `AskAgentCore`, which depends on `AskAI` (ADR-0009), not in a separate `AskAgent` target.

Slices:
1. Session payloads for agent turns.
2. Context into requests.
3. The tool protocol (with `0011`).
4. The loop with abort.
5. The interactive loop, after `0013`.

## Progress: headless and working (2026-10-18)

Slices 1–4 have landed:
- session payloads for agent turns;
- context into valid requests, with named repairs;
- the tool contract;
- `AgentLoop`, with abort, a turn limit and `pause_turn`.

`ask -p` runs it with the four tools. `Scripts/probe-agent-run.py` proves the binary end to end against a fake server, including SIGINT mid-command.

Per-turn cost with an instant provider: 33 µs fresh and 210 µs after 500 turns.

**Owed:**
- slice 5, the interactive loop (after `0013`);
- steering and follow-up messages;
- resuming a session (`--continue`, which needs a lock);
- the first live run (needs the user's `ask login`).

## Robust runs (2026-10-19)

- **Retry with backoff** for transient failures (RetryAdvice, RetryPolicy): never after anything of the
  attempt was shown.
- **Continuation after the output-token limit:** a cut-off tool call is dropped, and a visible user entry asks
  the model to continue.
- **`--max-turns`.**
- **Token usage** on the status line and at the end of `-p`.
- **AGENTS.md / CLAUDE.md** discovery.

Still owed for full runs: resume, compaction, steering, jobs and waits.

## Audit (2026-10-19)

Delivered since this entry's last progress note: the interactive screen (0013), resume (0029), compaction (0030),
jobs and waits (0031), configuration and reload (0039, 0041), slash commands, and the sandbox (0017, 0018).

At that audit two things kept it open, named in its own "Done when" and in "Steering and abort":
- **Steering and follow-up messages.** A message typed while a turn runs is refused today ("a turn is still running").
  It should queue and enter after the current turn (steering) or after the run (follow-up), and abort should return
  queued messages to the editor.
- **The budget.** `0007` has not re-derived the action-to-action budget against a real action, which this entry
  makes a condition of being done.

## Steering and follow-ups delivered (2026-10-20, ADR-0040)

Enter during a run queues steering after the current response and all its tools; `/follow-up TEXT` (or
modified Alt+Enter) waits until the agent finishes. Each is persisted once and acknowledged then. Abort or
failure returns only unsent messages alongside the draft. Completion races and late acknowledgments are tested;
real-PTY probes J–L inspect requests and archives, and a live Haiku run follows both kinds of input.

Only **0007's re-derived action budget** now keeps this entry open. Multi-line editing and interactive
session/model commands have their own units, 0049 and 0050.
