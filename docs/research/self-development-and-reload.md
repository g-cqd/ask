# Developing ask from within ask: binary and configuration reload (2026-10-19)

The user wants to develop ask from inside ask. That needs a way to reload the binary without losing the
session, and configuration that reloads on demand or automatically, as the configuration itself says.
Inject (InjectionIII) was the prompt. These probes decided how.

## Probes (macOS 27.2, Swift 6.4)

| Claim | Probe | Result |
|---|---|---|
| A running binary survives being rebuilt | A resident SwiftPM executable; change its code; `swift build -c release`; compare content hash and inode | The content changed and the **inode changed**: the linker writes a new file. The old process ran on, and the new binary printed the new code. (A comment-only edit left the inode unchanged because nothing was relinked.) |
| Terminal raw mode survives `exec` | Set raw mode in a PTY child, `exec` into `stty -a` | `-icanon -echo` is still set: termios belongs to the tty, so the alternate screen and modes persist across `exec` |
| An editor-style save is visible to a watcher | kqueue `EVFILT_VNODE` on the file and its directory; write a temporary file, rename it over | The file reports **DELETE** and the directory **WRITE**; the old descriptor still reads the **old** content. An in-place save reports WRITE, ATTRIB and EXTEND on the file |
| Config can be hand-editable without a new dependency | AemiJSON's parse options | `JSONParseOptions.json5` (comments, trailing commas) |
| Rebuilding ask in its own tree contends with other work | A probe while another session ran `swift test` | `swift build` waits on `.build/.lock`. A reload's build step must report that it is waiting, not appear hung |

## Proposal: reload by re-exec, not by patching code

Inject-style hot patching (InjectionIII interposes recompiled code into a running debug process) is
rejected for ask:
- Swift code cannot be safely unloaded;
- it is debug-only by design;
- ask's state already survives in the session file.

**Re-exec costs one cold start (10–20 ms measured) plus the build.**

`/reload`, or automatically when the watched binary changes and ask is idle:
1. **Only between turns.** A running turn finishes or is aborted first. Background jobs, once they exist,
   are stopped or listed.
2. **Optional build step** from configuration (for example `swift build -c release --product ask`), shown in
   the transcript. A failure or a lock wait is reported, and ask stays on the current binary.
3. **Self-check the new binary** (`ask --self-check` with a timeout: it starts, prints its build identity,
   exits 0). Never `exec` into a binary that cannot start.
4. **`execv(new, ["ask", "--resume", <session>, "--reloaded-from", <old build>])`.** Every descriptor other
   than the tty must be close-on-exec (TerminalKit's signal pipe already is).
5. **The new process** resumes the session, redraws in full, and says
   "Reloaded from <old> to <new> in N ms".

**Constraint this places on the design:** anything that must survive a reload must be persisted. The session
already is; the editor's draft, scroll position and queued messages would need a small state file, or are
documented as lost.

**Prerequisite:** resume (`--resume <session>`), roadmap 0008/0009, which is owed anyway.

## Proposal: configuration with on-demand and automatic reload

- **Files:**
  - `~/.config/ask/config.json` for the user;
  - `<project>/.ask/config.json` for the project, honoured only in a trusted project, like project-hooks'
    trust, because a project file could change the model, tools or sandbox.
  - JSON5 through AemiJSON.
- **Precedence:** defaults < user < project (trusted) < environment < flags. The session records the
  effective configuration.
- **`reload`:** `manual` (`/reload-config`, and `/reload` also re-reads), or `auto`.
- **Auto mode** watches the *directory* with kqueue and re-opens the file on DELETE or RENAME, debounced
  because one save is several events.
- **A new configuration** is parsed and validated whole. If valid, it applies; if not, the old one stays and
  the error names the file and line. Never a silent partial apply.
- **Settings declare whether they apply live** (model, thinking, limits, display) **or need `/reload`**
  (terminal modes, build settings). A change of the second kind says so.
- **Security, from ADR-0020:**
  - only the user widens policy. If the agent edits a config file and auto-reload applies it, the model has
    widened its own sandbox;
  - so the config paths join the default write-deny list;
  - a change that widens policy needs confirmation however it arrives.

## Order, given these

Resume first; then configuration (the loader, layered files, manual reload); then binary reload; then
automatic watching for both. Developing ask inside ask also needs long builds and tests to behave: the jobs
and waits proposal, and full-output files.
