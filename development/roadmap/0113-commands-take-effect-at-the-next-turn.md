---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0113 — Commands take effect at the next turn, not only when idle

Owner wish (2026-10-28 19:38): a model change should apply at the very next turn instead of waiting for the session to be idle. The same goes
for every command that does not need an idle session (`/tree` does and cannot work this way). Even fork could act on the fly. The owner
asks for an assessment, to be confirmed before any change.

## Still owed (assessment first)

- List every command with what it touches: settings read at the start of a turn (model, thinking, compaction), the session file, the
  transcript, running tools.
- Classify each: applies at the next turn, applies at once, or needs idle, with the reason.
- For fork while running: what a fork of an unfinished turn contains, and whether the running turn continues in the original.
- Bring the table to the owner before implementing.

## Assessment (2026-10-30), for the owner to confirm

Today the screen's own commands (`/help`, `/quit`, `/jobs`, `/sidebar`, `/verbose`, `/follow-up`, `/continue`) work during a turn, and
every command the conversation runs is refused ("A turn is still running"). The loop is built from the settings at the first prompt and
rebuilt after a change, so a turn runs on the settings it started with.

| Command | What it touches | Proposed while a turn runs | Why |
|---|---|---|---|
| `/model` (same connection), `/thinking` | the model or effort of the next request | **the next request**, inside the running turn | the loop rebuilds the request each time; context window and compaction are recomputed then |
| `/model` (another connection) | the provider | **the next prompt** | reasoning belongs to the protocol that issued it (ADR-0033): a provider switch inside the tool loop would replay another protocol's reasoning |
| `/config show`, `/mcp` | nothing (they read) | **at once** | read only |
| `/config` (the editor) | the settings files | **at once**; what it saves applies at the next prompt, as a file change already does | the watcher already defers to the end of the turn |
| `/login` | credentials of an account | **at once** | the sign-in's own questions take the input, as an approval does |
| `/logout` | credentials | **at once** for another account; **after the turn** for the one in use | the turn would fail on its next request |
| `/fork` | a new session file | **at once**, cut at the last entry written | the session is append-only and entries are written whole, so the fork holds every finished step; the running turn goes on in the original |
| `/skill:NAME` | a prompt | **queued**, as a typed message is (steering or follow-up) | it is a message |
| `/compact` | the context the turn is using | **after the turn** (queued, said so) | rewriting the context under the running turn would change what it sends mid-way |
| `/new`, `/resume` | which session is written | **after the turn** (queued, said so) | the running turn writes to the current session |
| `/rewind` | the session's leaf | **after the turn** | the owner's own exception |
| `/reload` | the process | **after the turn** | it replaces the process |

"After the turn" means the command is accepted, shown as waiting (as a queued message is), and runs when the turn ends; Esc or a
stop cancels it. Nothing waits on the person to type it again.

