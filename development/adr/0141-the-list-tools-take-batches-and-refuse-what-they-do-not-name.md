---
status: accepted
date: 2026-11-01
---

# 0141 — The list tools take batches, typed and limited, each change safe to repeat

Builds on ADR-0140 (the task list and the ideas, kept as their changes); roadmap 0191.

## Context

Converting the roadmap into this session's task list took about 260 calls for what were two acts: "add these 129" and "these are
done". Measured on the 0179 and 0180 tools:

- **One change per call.** No list of changes, no list of ids, no ranges; a task made done took two calls (add, then done).
- **Untyped input.** Every field was a string or "string or array"; `action` had no enum; an unknown field was ignored, so a misspelt
  one changed nothing and said nothing. A number id and a `t3` id were both accepted.
- **No limits.** Any length of title, any number of tasks.
- **Not safe to repeat.** A retried `add` made a second task; a model that cannot tell whether a call went through cannot retry.
- **Reading does not scale.** `list` returned every open task; at 181 tasks a read is several thousand tokens, and there is no
  filter, no count, no limit.
- **Links within one call** needed the id a task would get, guessed in advance.
- **No structure beyond links**: the roadmap number, the group and "blocked on the owner" went into titles.
- **Ideas and tasks did not know each other**; `show` printed a one-line idea twice.
- The two definitions cost 1,333 bytes per request (818 tasks, 515 ideas), every turn.

## Decision

One shape for both tools: a call carries `changes`, a `read`, or both (the changes first, then the read, so a change and the view
after it cost one call). Nothing else is accepted: an unknown field, a field an operation does not take, or a value outside its limits
refuses the call, naming the change and the field.

### Lean first

Both definitions are sent on every request, so they say only what the schema cannot, and the schema says only types and enums.

- Ids, tags and links are **one space-separated string** (`"ids": "t3 t5-t9"`), not arrays: shorter in the schema and in every call.
- `@1`, `@2` name this call's first and second add, so a batch links what it makes without a naming field.
- No `full` flag: a read by `ids` shows those entries in full; a listing shows a line each.
- `move` takes `before`: an id, or `end`.
- Ideas have one operation, so their changes have no `op`.
- The limits are not in the schema (lengths, counts, patterns cost bytes on every request); the decoder and the planner enforce them
  and a refusal states them. Unknown fields are refused by the decoder, not by `additionalProperties`.
- The schema is built from a typed `ToolSchema` (AskAI), written through the stream writer: right by construction, no `try!`.

Measured: 1,333 bytes for the two definitions before (untyped, one change a call), 1,351 after (typed, enums, batches, reads),
pinned by a test so they do not grow unnoticed.

### Changes: a batch, all or nothing

- A call's changes (1 to 100) are planned on a copy of the list, in order; if any is refused, none is made and the answer names it
  (`change 3 (state): there is no task t9.`). The batch is kept as **one record** (`kind: batch`), so a torn write loses all of it or
  none, as a crash between two records could not promise.
- Tasks: `add` (title; detail, state, tags, blocked_by, related), `edit` (one id; title, detail, tags), `state` (ids, state), `move`
  (one id; before), `link` and `unlink` (ids; blocked_by, related), `remove` (ids). Ideas: a change sets `state` (acknowledged,
  fulfilled, dismissed) for `ids`, and `task` names the task one became. The model cannot write or edit an idea.
- **Ids are strings**: `t3`, a range `t5-t9`, `@n`. A number alone is refused: there is one way to write an id.

### Each change safe to repeat

A call repeated after a lost answer changes nothing the second time, and says so (`already so: t1–t2 (2)`):

- `add`: **a title names one task.** An add whose title exists with the same detail is that task, whatever later changes did to its
  state, tags and links, so a repeated batch finds its tasks instead of resetting them; with another detail it is refused.
- `state`, `link`, `unlink`, `move`, `edit`, a mark: setting what is already so is no change.
- `remove` of a task removed before is no change; of an id never given it is refused, so a typo is never silent.

### Limits

| | |
|---|---|
| changes per call | 100 |
| ids a call resolves, ranges expanded | 1,000 |
| tasks or ideas in a list | 2,000 |
| title | 1 line, 120 characters, unique |
| detail | 4,000 characters |
| tags | 8 a task, each `[a-z0-9-]{1,24}` |
| read: `limit` | 1 to 200, 50 by default |
| read: `text` | 80 characters |
| an idea's line in a listing | 120 characters, `…` |

### Reading

`read`: `view` (tasks: `open`, the default, `done`, `all`, `summary`; ideas: `new`, `open`, `all`, `summary`), `ids`, `text`,
`limit`. A listing says how many it left out and, in the open view, how many are done; a summary counts states, blocked tasks and tags.

### Search: words now, the index of roadmap 0181 later

`text` is a search, not a substring: every word of it must appear, case-insensitively, in a task's title, tags or detail (an idea's
text); matches are ordered by the earliest field their words are in, the title first, then by place in the list. This is the lexical
search 0181's research starts from, at no cost for lists of this size. When 0181 lands an index (ranked, then semantic), it answers the
same `text` field: the tools' shape does not change, only the order and reach of what a search finds.

### Kept

- `SessionTask` gains `tags`, and `made` and `closed` times; an `Idea` gains the `tasks` it became. Old records read as before
  (absent fields are empty); the ideas keep the layout 0180 wrote, one key naming the change.
- A record of a kind this build does not know (one a later ask wrote) makes the list **read-only** instead of dropped and rewritten,
  so an older ask never destroys a newer one's work.
- Title uniqueness and the limits are checked when a change is planned, not when one is replayed, so a list written before them still
  reads whole.

## Consequences

- The roadmap conversion becomes two calls. Retrying is always safe.
- The definitions are typed and batched for 18 more bytes than before (1,351 against 1,333).
- Two tasks can no longer share a title; the model is told when it tries.
- An ask from before this record reads a batch record as damaged. Going back to it after batches are written loses them; the list
  file is not meant to travel backwards.
