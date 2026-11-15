# `ask serve`: the design proposed (2026-11-14)

**Accepted on 2026-11-14 as proposed (ADR-0154), with one correction: `AskACP` depends on AskTUI's `Conversation`, not on
`AskSession`.** Kept as written for what was proposed.

What ADR-0153 decided: ACP v1 is the protocol, a served session is the conversation, the family's code is used where it exists.
What it left: everything below. This is a proposal for the owner to read before any code; nothing here is decided, and the open
points at the end are questions.

Read from the ACP v1 specification on 2026-11-14 (overview, prompt turn, tool calls, session setup, elicitation, extensibility).
Not read: initialization's full capability list, content blocks, slash commands, session list, authentication, the schema, the
compatibility kit. A claim below that depends on one of those says so or is in the open points.

## Proposed

1. **One command.** `ask serve`, on standard input and output, one JSON-RPC message a line. Standard output carries protocol
   messages and nothing else; ask's own words go to standard error. No `--acp` beside it.
2. **The wire.** `JSONRPCConnection` with line framing, `FileDescriptorChunks` on standard input, AemiJSON for the typed messages.
3. **A session is an `AgentConversation`.** The ACP front is a second consumer of the conversation's updates, beside the screen's
   controller, and a second source of its inputs (a prompt, an answer, a cancel).
4. **A new target, `AskACP`**, above `AskSession` and below the `ask` executable: the protocol's types and the mapping. Nothing
   below it learns the protocol's name.
5. **What maps, maps to ACP's own words** (the table below). What ACP has no word for is not sent in the first version, and is
   listed; it does not go into a field ACP owns.
6. **Approvals are ask's**, asked through the client: the policy is the configuration's, as on the screen, and
   `session/request_permission` carries the choices the screen would show. ask keeps what "always" means (the session, a command's
   prefix) and says so in the option's name, as the specification asks.
7. **Secrets never travel in a form.** The specification forbids it. A command that needs a key or a code under serve says to run
   `ask login` in a terminal.
8. **ask's tools stay ask's.** Files are read and written by ask under its sandbox, not through the client's `fs/*` or
   `terminal/*`. The session's `cwd` is the workspace the sandbox already confines writes to.

## The mapping

| The conversation says | ACP |
|---|---|
| assistant text, thinking | `agent_message_chunk`, `agent_thought_chunk` |
| a prompt taken (typed, queued, replayed) | `user_message_chunk` |
| a tool started | `tool_call`: id, `title` (the block's header), `name`, `kind`, `rawInput`, `locations` for a path |
| progress, a job's output | `tool_call_update` with content |
| a tool finished | `tool_call_update`: `completed` or `failed`, its text; a `diff` for `write` and `edit` |
| an approval to ask | `session/request_permission`; `cancelled` denies |
| the `question` tool | `elicitation/create`, form mode, when the client advertises it; otherwise the tool is not offered, as under `-p` |
| a notice | `notice`, when the client advertises `session.notices` |
| compaction started, finished | `compaction_update`, when the client advertises `session.compaction` |
| tokens in the context | `usage_update` |
| the conversation's name | `session_info_update` |
| skills and slash commands | `available_commands_update`; a prompt that starts with `/` is ask's command, as typed on the screen |
| the turn ended | the `session/prompt` response: `end_turn`, `cancelled`, `max_turn_requests`; a failure is a JSON-RPC error |
| `session/cancel` | what Esc does |
| `session/load` | the session file replayed as updates; the id is the session file's name |
| `mcpServers` of a session | added to that session's hub: stdio and HTTP (`mcpCapabilities.http`); SSE is not built |

Not sent in the first version: threads and asides, the runners list, the git and status segments, the pickers' rows, the
configuration editor, drafts. They are the screen's furniture; each is a candidate for an extension later, asked for first.

## Open, to settle before the code that needs them

- **A prompt while a turn runs.** The screen steers (Enter) or queues. ACP's page does not say what a second `session/prompt`
  means. Proposed: it steers, as Enter does, and both requests answer when the turn ends.
- **The extension's name.** The specification asks for a reverse-DNS prefix of a domain the author controls. Which domain is
  the owner's to say; nothing is sent under an extension name until then.
- **The types.** Written by hand for the subset used, or generated from ACP's published schema. Hand-written is proposed: about
  thirty types, each tested against the specification's own examples.
- **Multi-select questions.** Whether form mode's restricted schema has an array of choices was not read; if not, a
  multiple-choice question is asked as one question a choice.
- **Sign-in through ACP** (`authenticate`, the terminal method): not designed here.

## The order of work

1. A spike: `initialize` answered through AemiJSONRPC inside ask's package, under its strict flags. It can fail (the product, the
   flags, the import rule for AemiRuntime).
2. The session's folder instead of the process's, with the screen's behaviour pinned first.
3. `session/new`, `session/prompt` with text and thinking, `session/cancel`; `Scripts/probe-serve.py` drives it.
4. Tool calls and permissions.
5. `session/load`.
6. Commands, compaction, usage, notices, the title.
7. Elicitation.
8. ACP's compatibility kit as an independent oracle, then the owner's check in Zed.
