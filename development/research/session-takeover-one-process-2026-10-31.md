# Taking over a running session in one process: the ways compared (roadmap 0115)

2026-10-31, the revision the owner asked for. The first note (`session-takeover-2026-10-31.md`) proposed a headless host per session
and the screen as its client. The owner set that aside: **one process per session**. This note compares the ways a screen can reach a
loop that runs in another `ask` process, what each costs in jobs, approvals and a turn in flight, and then takes the owner's other two
answers: an unattached session's lifetime is a setting, and the screen that loses its session stays. The survey of other harnesses in
the first note stands; nothing here is built.

## What constrains every way (read from the code, 2026-10-31)

- **Jobs are the loop's children.** `Job` runs each command in a session of its own, but its output arrives through pipes the loop's
  process reads, and only that process can reap it with its exit status. `ask` exiting stops every job (`JobTable`), and `/reload`
  refuses while one runs (`AgentConversation+Reload`). A loop that moves to another process loses its jobs. Handing over the pipes
  (`SCM_RIGHTS`) would not help, because the exit status is the parent's alone.
- **A turn in flight lives in memory.** The loop writes a response to the file only once it is complete, and a tool result when its
  call finishes (`AgentLoop.record`). A reply that is still streaming exists nowhere else. `SessionReplay` finishes a call that has no
  result as interrupted.
- **An approval or question that is waiting is in memory too.** What the person allowed for the session (`SessionGrants`) can already
  cross a process boundary: `/reload` writes it to a file only the person can read, and the new process takes that file (0159).
- **The sandbox is per command, not per process.** `JobProcess` runs `bash` under `sandbox-exec` with the session's profile
  (`SeatbeltProfile`). Any `ask` process can run a session's tools under that session's own policy, so no way below is ruled out by
  the sandbox.
- **The terminal belongs to one process.** TerminalKit's signal relay (`CTerminalSignals`) has one owner per process, for SIGWINCH,
  SIGINT and SIGTERM. Nothing handles SIGHUP, so closing a terminal ends its `ask`, its session and its jobs today.
  `POSIXTerminalConnection` takes any file descriptor, so a process can draw on a terminal it did not start in.

## The ways

**A. The owner serves its session.** The process that holds the session keeps its loop. It listens on a Unix-domain socket beside the
session file, and another `ask` attaches as a client. The client's screen is fed `ConversationUpdate`s over the socket, after a
replay, and sends back prompts, steering, interruptions, answers and commands. Nothing moves, so jobs, approvals and a turn in flight
are untouched. The cost is the protocol, and its surface is everything the screen and the conversation say to each other. That
includes the interactive commands that run inside `AgentConversation` today, such as `/config`'s editor, `/tree`, `/model` and the
selector, and each must be made remote or refused on a client. This is the first note's protocol without the host process.

**B. Hand over through the session file.** At an idle point the owner writes its grants, as `/reload` does, and releases the lock.
The taker takes the lock, replays the file and starts the loop with that session's configuration, context, skills and MCP servers.
- **Jobs:** stopped, or the hand-over refused while they run, as `/reload` does.
- **A turn in flight:** waited for, or interrupted. An interrupted reply is lost, and its open calls are finished as interrupted.
- **A waiting approval or question:** answered first, or cancelled with the turn.
- **Other costs:** MCP servers restart (seconds, not milliseconds). Taking it back is a second hand-over with the same costs.

Little code is new (resume plus 0159). But it moves a session only when it is idle with nothing running, and that is close to quitting
here and `--continue` there.

**C. Lend the terminal.** Instead of the loop moving to the screen, the screen moves to the loop.
1. The taker stops reading its terminal.
2. It sends that terminal's descriptor to the owner over the owner's socket (`SCM_RIGHTS`, after `getpeereid` shows the same user).
3. The owner opens a second screen on that descriptor, over its own `AgentConversation`.

Nothing moves but a descriptor, so jobs, approvals, a waiting question and a streaming reply all go on exactly as they were. Every
command, the editor, `/config` and the selector work unchanged, because the same code runs where the session lives.

The socket carries only a few small messages: the descriptor, the terminal's size (SIGWINCH reaches the taker, the foreground
process), "give it back", and "taken back". The taker's own session keeps running in the taker, in the background, as the wish asks.

Its costs:
- **TerminalKit:** a screen that owns no signals (the relay has one owner per process), and capabilities and appearance probed per
  connection, not per process. The lent terminal may be another terminal app.
- **The owner draws two screens on one main actor.** Each keystroke is still one screen's frame, so the 4 ms input budget is per
  frame as before. The second screen's rows add to the owner's memory: to be measured against the 20 MiB active budget.
- **A taker that dies mid-loan** leaves the owner holding a terminal whose shell has come back. The socket closing tells the owner
  at once, and the owner stops that screen and closes the descriptor. **An owner that dies** leaves the taker with its terminal: it
  restores the terminal (raw mode, alternate screen) and shows its own session with a notice.
- **Trust:** a terminal's descriptor is full control of that terminal. The socket is 0600 in a 0700 directory and the peer is
  checked, the same trust as the session files themselves.

**Others considered.**
- **Moving the jobs' pipes with `SCM_RIGHTS`:** rejected, because the exit status stays with the parent.
- **A tmux-like pty owner:** rejected, because it is a second process.
- **A terminal multiplexer's own panes:** outside ask, and they show a session, not take it over.

## How they compare

| | A. Owner serves | B. Hand over | C. Lend the terminal |
|---|---|---|---|
| Jobs | kept | stopped or refused | kept |
| Approvals, questions waiting | kept, sent over the protocol | answered or cancelled first | kept, unchanged |
| A turn in flight | kept, streamed over the protocol | waited for or lost | kept, unchanged |
| Commands, editor, selector | each made remote, or refused | all, after the move | all, unchanged |
| Taking it back | detach | a second hand-over | "give back" |
| New code | a protocol over the whole screen–conversation surface | small: 0159 plus resume | descriptor passing; screens without signals |
| Memory | the client's screen | none | the owner's second screen |
| Processes per session | one | one | one |

## Recommendation

**C, lend the terminal, with B as the way out for an owner that is leaving.** C is the only way that keeps everything a session has
without making it remote. A's protocol is the largest piece of work in any design and would buy remote clients, which nobody has asked
for. B alone moves only idle sessions, but it fits one case well: an owner whose own terminal closes, while a lent screen shows its
session and the setting below says to end. That owner can hand its session to the taker when it is idle with no jobs, instead of
ending it.

## The owner's answers, applied

**An unattached session's lifetime is a setting.** A session is unattached when no terminal shows it. With C, that happens only when
its process's own terminal has closed and nothing has borrowed one. Proposed: `session.unattached` (the name is to be agreed), one of:
- `"end"`: today's behaviour, where closing the terminal ends the session;
- `"whileWorking"`: the session lives until its turn and its jobs end, then ends; it stays resumable from its file;
- a duration, such as `"1h"`: it lives that long after its last activity;
- `"always"`.

Surviving a terminal means SIGHUP handled, the screen stopped and nothing written to the closed terminal; the loop and jobs carry on.
The default is the owner's call. This note proposes `"whileWorking"`: it never loses work in flight, and it never leaves an idle
`ask` around.

**The screen that loses its session stays.** When another terminal takes the session, the owner's own terminal does not close. It
switches to a short notice above the session list, the same selector that Left twice opens:
- the notice names the terminal that has the session ("shown in another terminal since 14:02");
- the lost session is the first row, and Enter on it takes it back: the borrowing screen gets "taken back", returns its terminal to
  the taker, and the taker shows its own session again with the matching notice;
- the other rows attach as from anywhere.

While the session waits on the person, the notice says so, so that a terminal left behind still tells you something wants an answer.

**The bottom row.** The row of background sessions below the jobs stays as the first note proposed. With C those sessions are this
process's own, or ones that lent screens point at, so the row needs no protocol beyond presence.

## Phases, each red first

1. **Presence and listing.** Held locks plus a presence file holding the pid, the project, the state, the name and the socket path;
   the Left-twice selector, read only. This is the first note's phase 1, unchanged.
2. **Surviving the terminal**, under the setting above: SIGHUP handled, the screen stopped, the loop kept. It is useful alone: closing
   a terminal no longer kills a long turn. Probe: a PTY closed mid-turn, with a job running.
3. **A spike before building C:**
   - two screens in one process, on the PTY emulator;
   - TerminalKit's screen without signals, and capabilities probed per connection;
   - the owner's RSS with a second screen, and input latency on both screens;
   - a taker killed mid-loan, and an owner killed mid-loan.

   The spike decides C or A. If two screens in one process cost more than the budgets allow, A becomes the fallback.
4. **Lending:** the socket, descriptor passing, the peer check, resize, give back and take back, and the lost screen with its notice.
5. **Hand-over on the way out** (B), for an owner that is ending with a borrowed screen showing its session, idle and with no jobs.
6. **Names** with Foundation Models, and the bottom row's colour, as the first note proposed.

## Questions for the owner

1. **C, lend the terminal, over A, the owner serving a protocol**, with the spike in phase 3 deciding if C's memory does not hold?
2. **The lifetime setting's default:** `"whileWorking"` as proposed, or `"end"` (today's behaviour)?
3. **Is the active memory budget (20 MiB) per process,** so that it includes a second screen while a terminal is borrowed?
