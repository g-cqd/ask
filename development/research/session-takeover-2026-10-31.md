# Taking over a running session: survey and design (roadmap 0115)

2026-10-31. The owner's wish: pressing Left twice lists the sessions running elsewhere; choosing one puts it on this screen; the session
that was here goes on in the background and shows at the bottom when it waits; the screen that was showing the chosen session quits
its view. This note surveys how other harnesses do it, then proposes a design. Nothing here is built or decided; the questions at the
end are the owner's.

## How others do it (read 2026-10-31, from each project's current documentation)

| Harness | Where the loop runs | How a screen reaches another session |
|---|---|---|
| **Claude Code** (`code.claude.com/docs/en/agent-view.md`) | Background sessions are each **their own process under a supervisor**, a background service started on first use. It restarts a process that died, stops one idle and unattached for about an hour (the conversation stays on disk and resumes on the next reply), and lets a session be pinned to keep it running. If the supervisor stops, its sessions stop within a minute unless a new one connects. | `←` on an empty prompt backgrounds the session and opens *agent view*, a table of sessions grouped by state (needs input in yellow, working, done, stopped in grey), each row with a name, its activity and age. A one-line summary per row is written by a Haiku-class model and refreshed during long turns. `Space` peeks (last output or the pending question) and can reply; `Enter` or `→` attaches; `←` on an empty prompt detaches. The footer counts waiting sessions (`← 2 agents`) and briefly shows finished ones. `claude attach`, `logs`, `stop` and `restart` do the same from the shell. |
| **OpenCode** (`opencode.ai/docs/cli`) | A **server** (`opencode serve` or `web`) holds the sessions; the TUI is a client. | `opencode attach <url>` attaches a terminal to a running server, with `--session` and `--continue`; several clients can watch one server. Basic auth for remote servers. |
| **Codex** (`codex-rs/app-server/README.md`) | An **app server** speaking JSON-RPC over stdio or WebSocket loads *threads*; clients subscribe. | `thread/resume` and `thread/fork` load a thread; events go to every connected client until `thread/unsubscribe` or disconnect. A pending approval is replayed to the next capable client that connects. |
| **pi** (`packages/coding-agent/docs/rpc.md`) | One process per session; **RPC mode** drives it as a long-lived subprocess over JSONL on stdin and stdout. | No takeover between terminals: an integration owns the process it spawned. Commands in, session events out (run, message, tool, queue, compaction, retry). |
| **Amp** (`ampcode.com/docs/markdown/cli/remote-control`) | Threads are kept on Amp's servers. | *Cross-client access* continues a running CLI thread from the web, under a workspace setting. |

What they agree on: the loop lives somewhere other than the screen's process (a supervised process, a server, a host subprocess), a
screen is a client that can come and go, and a session that waits on the person is the one to surface. Nobody moves a running loop
between processes: they move the screen.

## What ask has to build on

- **A session has one writer, by `flock`** on its file (ADR-0024, `SessionLock`), released by the kernel however the holder ends.
  "Is this session running?" is therefore already answerable without a registry that can go stale: try a shared non-blocking lock.
- **Replay** (`SessionReplay`) rebuilds a screen from the file through the same updates a live run sends, so attaching is a replay
  followed by live events.
- **The screen consumes `ConversationUpdate`s** mapped from `AgentEvent`s in the composition root; AskTUI does not see the loop
  (ADR-0009). That boundary is where a socket would go.
- **Jobs** (yielded `bash` processes) are children of the process running the loop, so the loop cannot move to another process without
  killing or orphaning them. This is the strongest constraint, and why the others move the screen.

## Proposed design

**1. A host per session, the screen a client.** An interactive `ask` spawns its session's host, the same binary in a headless mode,
with `posix_spawn` and `POSIX_SPAWN_SETSID` so closing the terminal does not hang it up. The host holds the session lock, the agent
loop, the tools and their jobs, the MCP clients and the keep-awake assertion (0090). The screen keeps the editor, layout and drawing
(input stays in the 4 ms budget, with no round trip) and talks to its host over a Unix-domain socket beside the session file
(directory 0700, socket 0600, peer checked with `getpeereid` as the same user). Taking over is the screen detaching from its host
and attaching to another; nothing moves but the screen.

- **Attach:** replay the file, then the live events after the last recorded entry (each event numbered, so none are lost or doubled in
  between), then any pending question or approval, as Codex replays one.
- **From the screen:** prompts, steering, interruption, answers to questions and approvals, model changes. **From the host:** events,
  its state (working, waiting for input, waiting for an answer, idle, ended) and its name.
- **One screen at a time.** A second screen attaching takes the session: the first one is told so and quits its view, as the wish
  says, restoring the terminal with a line naming the session and the screen that took it.
- **Wire format:** JSON lines through AemiJSON first, framed by length. Protobuf (wish, 0060) once AemiProtobuf is ready; the
  messages are designed so the swap changes framing, not meaning.

**2. Finding sessions: the locks, plus a presence file.** A host writes `presence.json` beside its socket (pid, project path, session
path, state, name, last activity), rewritten on each state change. A session is listed when its lock is held. A presence file without
a held lock is stale and ignored. Listing reads only ask's own state directory. The sandbox (ADR-0115 and the seatbelt profile) must
let the screen connect to sockets there, and nothing else changes: an attached screen gains no rights in another session, which keeps
its own host's sandbox and approvals.

**3. When a host ends.** When its turn and jobs end and no screen is attached, it waits; past a limit (proposed: one hour, as Claude
Code does; `session.unattachedLimit`) it exits and the session stays resumable from its file. A host that crashes ends its session.
Nothing restarts it, because without a supervisor there is nothing to restart it: the file is intact and `--continue` resumes it.
**No supervisor or launchd agent in the first version.** A host is its own supervisor, which also keeps ask free of a login item.

**4. The screen's side.**
- **Left twice on an empty prompt** opens the selector of the other running sessions, mirroring 0117's selector. Each row has a name,
  state, project path and age; waiting sessions come first.
- **Background sessions on this screen** that wait or go idle show on one row at the very bottom, below the jobs, after a blank row,
  in a colour of their own: neither config purple (0106) nor debug yellow (0107). A click attaches to one.
- **Right twice** stays the continue gesture of the wishes; the two do not collide.

**5. Names, on the device only.** The host names its session with Apple's on-device model (Foundation Models, as the job-naming note
assesses), off any input path, falling back to the first words of the first prompt. A name is persisted in the session file, so it is
computed once per session and refreshed only on a long turn.

## Costs and risks

- **Cold start (50 ms):** spawning the host and connecting adds both processes' start-up; the screen can draw its first frame before the
  host answers, so the budget is measured to the first frame, and the host's own start runs in parallel. To be measured, not assumed.
- **Memory (15 MiB idle, 20 MiB active):** two processes per session. The split moves most of today's memory into the host; the screen
  should be small. The budget needs restating per process or per session. Owner's call (below).
- **Every event crosses a socket:** microseconds per event against an 8 ms action budget; streaming deltas are coalesced per frame as
  they are today.
- **One more failure mode:** a screen whose host died. It shows the session as ended, with the error, and offers to resume it.
- **Size:** the largest change since the loop itself. It touches the composition root, keep-awake, jobs and signals. It goes behind a
  setting (`session.host`: `inProcess` default, `detached`) until the probes and budgets hold, then flips.

## Phases, each red first

1. **Presence and listing, no split:** locks plus presence files; `ask sessions --running` and the Left-twice selector, read only,
   showing what runs elsewhere. Useful alone, and it settles the registry.
2. **The host behind `session.host: detached`:** spawn, socket, protocol, replay and live events; one screen. Probes for cold start,
   RSS, jobs surviving a closed terminal, and a crashed host.
3. **Take over:** attach and detach between sessions, the screen that loses one quits its view, the bottom row and its colour.
4. **Names** with Foundation Models.
5. **Default to detached**, once 2 to 4 hold their budgets.

## Questions for the owner

1. **Two processes per session**, a headless host and the screen: acceptable, and are the memory budgets per process or per session?
2. **An unattached, idle host's lifetime:** an hour (Claude Code's), until the last ask screen exits, or a setting with a default?
3. **The screen that loses its session:** quit to the shell, as the wish reads, or stay with a notice and a key to take it back?
4. **No supervisor in the first version**, so a crashed host is not restarted (its session resumes with `--continue`): acceptable?
