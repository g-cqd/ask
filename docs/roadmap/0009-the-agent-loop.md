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
