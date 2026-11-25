---
status: accepted
date: 2026-10-20
---

# 0049 — A connection keeps its own model names, apart from what the server lists

## Context

A named connection (ADR-0048) can offer many models, and a user wants short names of their own and a default, without retyping ids
such as `gpt-6.1-sol`. Two kinds of fact must stay apart: what the **server reports** (the catalog, ADR-0037: observed, expires,
refreshed) and what the **user chose** (names, a default, limits they state), which a refresh must never erase. Numbers: this ADR is
0043 because the `sandbox-strict` branch claims 0040 to 0042.

## The probes

Ledger in `development/diary/2026-10-20-45.md`.

- **Does it work on the real account?** On the user's real `work` connection: an alias and a default were added, `ask models work`
  listed the live catalog with the aliases below it, a run with no `--model` printed `Using work/fast, which is gpt-6-luna.`, and the
  session recorded `gpt-6-luna`, not `fast`. **CONFIRMED.** The completion was refused by the account's usage limit (HTTP 429); the
  request named the right model. Aliases were then removed again.
- **Does the real binary agree with the unit tests?** A 29-step scenario (now `Scripts/probe-connections.py`) found a bug no unit
  test could, because `Sources/ask` has none: `ask connections default NAME MODEL` refused every valid call (an inverted
  condition). **REFUTED at first, fixed.**
- **Does each rule fail without its test?** 12 mutations; the result is in the diary.

## Decision

1. **Aliases and the default belong to a named connection**, in `connections/<id>/aliases.json` (mode 0600, folder 0700), separate
   from the credentials (they are not secret) and from the catalog cache (they are not observed). A rename and a sign-out keep them; a
   removal retires the id, so a new connection of the same name starts with none. The default connections (`codex`, `anthropic`) have none.
2. **Names are lower-case words** (1 to 64 letters, digits, `.`, `_`, `-`). `--model X` means the alias if there is one, otherwise the
   server's id **unchanged**, so an id nothing lists keeps working and an alias can never narrow what is reachable. An explicit model
   beats the default; the default may be an alias or an id.
3. **An alias never hides a model.** It cannot be created with the name of a model in the cached catalog, and a request whose name is
   both an alias and a listed model is refused as ambiguous. With no cached catalog the creation check cannot run; the use-time check still does.
4. **No chains and no self-reference**, at creation and again at use (a hand-edited file may carry one). At most 64 per connection. The
   alias that is the default cannot be removed until the default is cleared; nothing falls back to another model silently.
5. **Limits the user states** (`--context`, `--max-output`) win over the server's and are shown as "as you stated"; limits they did
   not state still come from the catalog.
6. **A session records the server's id**, and every run that used an alias says which server model it stood for.
7. **A damaged alias file** refuses a run that relies on it (otherwise the default would silently become the catalog's first model) and
   does not refuse one that names a server model outright, with a notice. It is never rewritten. A file from a newer ask is refused. A
   hand-edited file is held to the rules `set` enforces.
8. Changes are transactions under a lock of their own (`aliases.json.aliases.lock`), through the atomic replace that credentials and
   the catalog hand-rolled (`AtomicFile`).

## Consequences

- Not done: a per-alias reasoning level (it needs the thinking setting, roadmap 0043, which waits for the configuration files another
  agent is editing); aliases for the default connections; choosing an alias in the screen's `/model`, which is that branch's code; `--json`.
- `ask models NAME` now needs the network (it already did) and prints the aliases only when it can read them.
- A hand-typed `--model` that is really an alias, with a damaged alias file, reaches the server as an unknown model and fails there.
