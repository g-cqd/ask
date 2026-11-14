# Security audit of ask — run 3: what came after run 2 (2026-11-13)

Scope: what was added since `d1d8353` (run 2, 2026-10-31), at `ee8f9b68`: the git state in the status bar and `#123` from GitHub
(0186), `fetch` (0237), `/goal` and `/loop` (0227, 0228), session search and its index (t209), `ask -p --json` (0234), the conversation
as a library (ADR-0149), MCP sign-in (OAuth), session encryption and its keys (0179), openers (ADR-0148), threads and subagents, the
Copilot sign-in, and the new CI workflows. Method as runs 1 and 2: reconnaissance, a threat model, hunting, then each candidate
reproduced on the real code (a failing test, or the release binary against a local server) or dropped.

**Partial, as runs 1 and 2 were:** one agent found and checked every candidate; there was no separate verifier. Nothing was sent to
a provider; the network was used for two public pages only.

## Threat model, added to run 2's

- **A folder the person opens**, whose `.git` they did not write: an archive unpacked, a folder shared or synced. (A clone carries
  no configuration; an archive of a repository does.) ask reads it before any approval.
- **A web page, an issue, a server's resource**: text written by anyone, entering the model's context, sometimes inside the
  person's own message.
- **A web server** the model is allowed to fetch from, which chooses what it answers: a redirect, an endless body.
- **A second model** that reads the run (the goal's judge) and whose answer drives the run.

## Findings, all fixed test first (each test red before the fix, or the release binary failing a live probe)

| # | Severity | Class | Where | Scenario | Fix |
|---|---|---|---|---|---|
| 1 | Medium to High | Command execution through a repository's configuration, CWE-78 | `GitStatus`, `ForgeReader` (0186) | ask ran `git status` by itself at every start, after each tool call and at each run's end. A repository's `.git/config` makes that run a command: `core.fsmonitor`, or a `filter` that `.gitattributes` names. Reproduced: opening the release binary in such a folder ran the command, with no approval and outside the sandbox. | `GitQuery`: every git ask runs by itself has `-c core.fsmonitor=false`, attributes read from the empty tree (`--attr-source`), submodules not entered. A git too old for it answers nothing. `GitQueryHardeningTests`, with a control that the fixture is hostile. |
| 2 | Medium | Server-side request forgery through a redirect, CWE-918 / CWE-601 | `FetchTool` (0237) | The system's HTTP client followed redirects by itself, so the checks `fetch` makes on a redirect never ran: a host the person allowed could send ask to any other, a private address included, and the result was labelled with the first address. Reproduced live. | Requests go through `URLSessionTransport` with redirects refused; each redirect is read and checked as a first address is; one to another host is refused with its address. |
| 3 | Low to Medium | Request forgery by name, CWE-918 | `FetchAddress` | A public name that resolves to a private, loopback or link-local address, or an address written as one number, passed the check, which read the name only. | The name is resolved before each request (`FetchResolver`) and refused when any address is inward. Left: a name that changes between the check and the connection (rebinding); the host's approval stands there. |
| 4 | Low to Medium | Resource exhaustion, CWE-400 | `FetchTool` | The whole body was read into memory before the 5 MiB limit applied. Reproduced live: a 100 MB answer was read whole. | The body is read as it comes and cut at the limit, the transfer with it; thirty seconds for the whole. |
| 5 | Low to Medium | Injection into a delimited section, CWE-74 | `FetchTool`, `ForgeReferences` (0186), `ResourceReferences` | A page could close the markers put around it; an issue's body and a server's resource sat in the person's own message, unmarked, and could end their section or start another (`--- task t1 ---`), so text after it read as the person's. | ADR-0150, `UntrustedText`: said to be data where it starts, unable to close its section; one-line fields made one line. |
| 6 | Low | Sensitive data in a cache, CWE-524 | `ForgeReader` | `#123` used the system's shared session: GitHub's answers (a private repository's, with a token) were kept in `~/Library/Caches/ask/Cache.db`, with cookies beside, in the clear and outside the session, which may be encrypted. Found on disk: nine answers. | The same transport (no cache, no cookie). `HTTPSessionStandardsTests`: no other file makes or uses a session. |
| 7 | Low | Injection through a second model, CWE-74 | `GoalHook` (0227) | What the judge concluded from the run's text went back to the working model as an instruction, with nothing saying whose it was. | The judge is told the run's text decides nothing; its answer is passed on as the judge's. |
| 8 | Medium (process) | Tests reaching the person's secrets, CWE-668 | `CredentialStorage`, `ConversationFixture` | Fixed earlier the same day (`1582275b`): a test host counted as a stably signed build and a fixture used the person's configuration folder, so a test run moved their credentials into the Keychain. | Only a build signed as ask counts; the fixture has its own folders. |

Severity is for this tool on a single-user Mac. 1 needs a folder whose `.git` another party wrote; 2 to 5 need a page, an issue or a
server the model was pointed at; none crosses an account boundary.

## Checked and sound

- **MCP sign-in.** Endpoints from a server's metadata must be https, or http to this machine (`EndpointPolicy`); the issuer must be
  the one asked; PKCE with S256 is required; metadata for another resource is refused (the conformance suite's `auth/resource-mismatch`
  passes). Tokens are kept as other credentials are.
- **Session encryption.** AES-GCM with random nonces; each frame authenticates the header's digest and its index, so frames cannot
  move between files or change order; keys are wrapped with their purpose authenticated; Argon2id with the file's parameters bounded
  (256 MiB, 10 passes, 16 lanes at most). The search index is sealed under a key derived for it, its file's name authenticated, and
  a clear one is removed when a session is encrypted.
- **Openers.** The program is the person's alone; a link gives an absolute path, a URL or a number to its arguments, with no shell
  between; a command asks unless allowed (ADR-0148).
- **Threads and subagents.** The conversation's approvals and grants; a subagent cannot write unless configured, has its own turn
  bound, the tools its definition names, and starts no subagent.
- **`!command`, `/loop`.** The person's own text; a loop's prompt is prefixed, so it is never read as a command.
- **Copilot sign-in.** Constant https addresses, the verification page pinned, the API's host pinned to `githubcopilot.com`,
  redirects refused.
- **`--json`, `search_session`.** No data the run did not already show; the search reads the current session only.
- **Workflows.** `probes.yml` and the new jobs of `mutation.yml` pin their actions by SHA and declare `permissions`; `issues: write`
  only in the job that reports a failure.

## Not covered, or left

- The 21 OAuth scenarios of the MCP conformance suite: its client does not sign in yet (roadmap 0123).
- An MCP server chooses the addresses of its metadata: ask makes a GET there (https only). The person configured the server.
- `fetch`: a name that resolves differently between the check and the connection.
- Roadmap 0183's research note (critical-software practices, an SBOM, signed and reproducible releases).
- No second reviewer. The owner's other Mac keeps what this run cleaned here: `~/Library/Caches/ask/Cache.db*`, `fsCachedData`,
  `~/Library/HTTPStorages/ask`, and the test items in its login Keychain.
