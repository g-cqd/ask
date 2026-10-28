# Other agents and tools, studied for ask (2026-10-19)

Read from each project's source at the commit named, not from memory. Purpose: decide what ask needs for real
use and full runs, what to borrow later, and what does not fit. The baseline the user set is "as
straightforward as pi first, extend later".

| Project | Commit | Language, licence | Verdict for ask |
|---|---|---|---|
| krzysztofzablocki/Inject | 67e3ee9 | Swift, MIT | **Not applicable.** Hot reload for UIKit/AppKit/SwiftUI through InjectionIII; ask is a CLI with no GUI to reload |
| rauchg/rst | 5a2d488 | Zig, Apache-2.0 | **Borrow techniques into TerminalKit's reset ladder** (below) |
| anomalyco/opencode | 501b15a | TypeScript, MIT | Reference for background jobs with automatic resume, a question tool and permission rules. Its architecture (client/server, plugins, many packages) is far beyond the pi baseline |
| mistralai/mistral-vibe | 4ae5c59 | Python, Apache-2.0 | Reference for managed shell sessions (cursor reads with a bounded wait, stdin), prefix-based command permissions, trusted folders, plan mode |
| openai/codex | 70b3bb6 (binary 0.163.0) | Rust, Apache-2.0 | Reference for unified exec (`yield_time_ms`, `write_stdin`), sandbox modes with `request_permissions` and prefix rules, `apply_patch`, a plan tool, secret redaction |

## pi, the baseline (1.3.0, installed)

- **Tools:** `read`, `write`, `edit`, `bash`, `find`, `grep`, `ls`. bash takes only `timeout`, and returns
  `output`, `truncated`, `full_output_path`, `exit_code` and `wall_time_seconds`.
- **Daily use:**
  - `pi --continue` and `/resume`;
  - automatic and manual compaction;
  - context files;
  - steering (Enter) and follow-up (Alt+Enter) while working, with abort returning queued messages;
  - Shift+Enter for new lines;
  - `/model`, `/thinking`, `/new`, `/session`, `/tree`, `/fork`;
  - `!cmd` and `!!cmd`;
  - `@` file references.
- **No per-call approval:** "use a sandbox for untrusted or unattended work".

## What ask lacks for real use, read from its code on 2026-10-19

- **No retry or backoff:** one `overloaded_error` or 429 ends a run.
- **No prompt caching:** `cacheRead` 0 live, roadmap 0024.
- **No context files:** `AGENTS.md` and `CLAUDE.md` are not read.
- **No resume, no compaction:** a long run eventually stops at the context limit.
- **No steering:** a second prompt while running is refused.
- **Single-line input, no slash commands.**
- **A response stopped by `max_tokens`** mid-tool-call fails assembly instead of continuing.
- **No `grep`/`find`/`ls`,** and no full-output file when bash output is capped.

## Waiting for things without the model polling

| Project | How a long or awaited command works |
|---|---|
| pi | Timeout only |
| opencode | `background: true` streams output to a file, and the agent **is resumed automatically when the command ends**. The description forbids polling ("sleeping and reading … is polling, not useful work") |
| mistral-vibe | Managed sessions: read from a cursor with `wait_seconds`, write to stdin |
| Codex | `exec_command` returns after `yield_time_ms` with output so far and a `session_id`; `write_stdin` sends input or waits again |

**For ask, a proposal to decide:** jobs plus waits that ask evaluates itself, event-driven, so the model makes
one call instead of a sleep loop:
- `bash` gains `yield_seconds`. Past it, the command becomes a job (id, output spooled to a file).
- `wait`: until `exit`, until a regex appears in a job's output, until a file exists or matches a regex,
  until a port accepts connections, or a plain duration. Always bounded by a timeout. Files are watched with
  kqueue (`EVFILT_VNODE`) and jobs through their output stream, so only the port check polls, with backoff.
- `job_input` and `job_stop`.
- Later, once steering exists (0027 seams), opencode's automatic resume when a job ends.

## Secure input

**Found:**
- Codex redacts secrets from displayed commands with regexes (bearer tokens, `sk-…`, AWS keys,
  `password=`), best effort, and keeps an encrypted local secret store (age).
- opencode uses masked prompts for its own auth.
- None of the three lets a user hand a secret to a running command without the model seeing it.
- ask's bash runs with stdin closed, so `sudo`, an ssh passphrase or a `read -s` simply fails.

**For ask, a proposal to decide:**
- **Masked entry** in the screen.
- **Secrets by name:** a tool asks for `GITHUB_TOKEN`, the user types it masked (or ask reads the Keychain),
  and the value goes into that one child's environment or stdin. Never the transcript, the session file, the
  request or the model. The model sees only the name.
- **Scrubbing:** exact-value scrubbing of known secrets from tool output before it reaches the model or the
  session (reliable), plus Codex-style regexes for unknown ones (best effort).
- **PTY mode:** when bash runs in a pseudo-terminal, a password prompt goes to the user's masked field, not
  to the model.

Swift `String` cannot be reliably zeroed; that limit is to be stated, not hidden.

## rst, for TerminalKit's reset ladder

rst resets a terminal in about 2 ms (the system `reset` takes about a second). Compared with TerminalKit's
`selectiveCleanup`, rst also:
- turns off synchronised output (`?2026l`; a program that dies mid-frame leaves the terminal buffering),
  focus events (`?1004l`) and insert mode (`4l`), and turns on wraparound (`?7h`);
- calls `tcflow(TCOON)` before `tcsetattr`, so output stopped by Ctrl-S cannot hang the reset. TerminalKit
  restores with `TCSAFLUSH`, which waits for output to drain, the blocking ask's PTY probes hit twice;
- refuses to run from a background job (`tcgetpgrp`);
- repairs only disabled control characters.

Each is a TerminalKit roadmap candidate, to be probed there.
