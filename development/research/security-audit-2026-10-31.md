# Security audit of ask — run 2: what run 1 did not cover (2026-10-31)

Scope: the "Not covered yet" list of roadmap 0153, at `d1d8353` (the first signed build): TLS and endpoint policy of the provider
clients, the extension host, skills' loading and trust, the image, PDF and video readers, the session parser, and the supply chain.
Method of `secure-coding`'s audit workflow, as in run 1: reconnaissance, a threat model per area, hunting, then each candidate either
reproduced on the real code (a failing test, or the release binary) or dropped in a false-positive pass.

**Partial, as run 1 was:** one agent found and checked every candidate; there were no separate verifiers. The peer CLIs on this Mac may
sign in with work accounts, so none was asked to review. Every reproduction ran locally, with scratch files and a dummy credential path.
Nothing was sent to a provider.

## Threat model

- **The model**, following instructions injected through a file, a web page or a tool result: it chooses tool arguments (paths, page
  specs, frame times) and may write in the workspace and the build caches.
- **A repository the person opens**: its `.claude/skills`, `.ask/config.json` and files are the author's. Only what `ask trust` approved
  is used, and approval names what the person saw.
- **A file handed to ask**: a session file passed with `--session PATH`, an image, PDF or video the model reads.
- **Another process of the same user**, unsandboxed: run 1 moved credentials into the Keychain (0110) to keep them from it.
- **The network between ask and a provider**, and the dependencies ask is built from.

## Findings, all fixed test first (each test red before the fix)

| # | Severity | Class | Where | Scenario | Fix |
|---|---|---|---|---|---|
| 1 | Medium | Library injection, CWE-114 / CWE-426 | `Scripts/sign.sh` | The signed build had no hardened runtime, so `DYLD_INSERT_LIBRARIES` loaded any library into it. Reproduced: a library with a constructor wrote a marker file when `ask --help` ran. That code runs as ask, which can read ask's Keychain items with no prompt, so 0110's protection could be bypassed by any process of the user. | Sign with `--options runtime`: `flags=0x10000(runtime)`, and the marker is no longer written. ask links only system libraries and needs none of the runtime's exceptions. Test: `test-sign.py`. |
| 2 | Medium | Link following, CWE-59 | `SkillDiscovery` | A project's `.claude/skills/setup/SKILL.md` that is a link to `~/.aws/credentials`. `ask trust --skills` shows the in-repo path; once trusted, the file is advertised and loaded into ask's process, which the sandbox's protected reads do not cover. A linked skills root does the same for a whole folder. | A project skill, or a project skills root, whose real path leaves the project is skipped with a notice ("links outside the project, so it is not read"). A root that links into the user's own skills still finds them as the user's. Tests: `SkillLinkTests` (4), `SkillTrustTests` updated. |
| 3 | Low–Medium | Privilege widening, CWE-269 | `Configuration.applying(session:)` | Writing defaults to the workspace (owner, 2026-10-29), but a session's recorded `write: anywhere` was layered in as if it narrowed. A planted session file (`--session PATH`), or one once run with `--write anywhere`, opened writing everywhere when resumed without the flag. | A record keeps only the scopes that narrow: `anywhere` is dropped from its write and read. Test: `SessionSandboxRecordTests`. |
| 4 | Low | Cleartext credentials, CWE-319 | `ProviderSettings+Target.swift` | `providers.json` `headers` (often an `Authorization` header) were sent over plain http to another machine; only `apiKey` counted as a credential. MCP already counts any header. | Any header counts as a credential: plain http only to loopback. Test: `ProviderSettingsTests`. Docs: `providers.md`. The owner has no `providers.json`. |
| 5 | Low | Resource exhaustion, CWE-407 / CWE-400 | `PDFReader.pages` | The model's page spec was bounded per range, not in all, and repeats were checked by a linear search. Three ranges of 10,000 took 21 s before a page was read; many more would hang the turn. | At most `PDFReader.maximumPages` (10,000) pages in all; repeats checked with a set. Test: `MediaReadTests`. |
| 6 | Low | Numeric conversion trap, CWE-681 / CWE-190 | `VideoReader.times` | A video file claiming an enormous length (9e18 s) read with `every` converted a frame count past `Int.max` to `Int`: a fatal error that ends ask, interactive session included. Reproduced in a test, which crashed the test process. | The count is clamped in `Double`; "wanted" becomes `Int.max`. Test: `MediaReadTests`. |

Severity is for this tool on a single-user Mac: none crosses an account boundary, and 1, 2 and 3 need a process, a repository or a
file the person let in.

## Hardening applied

- **Builds use exactly what `Package.resolved` pins**: `--force-resolved-versions` in `quality.sh`, `build-release.sh` and the
  release job of `quality.yml`. A dependency's revision then changes only in a reviewed commit, never by a re-resolve during a build.
  `swift package resolve --force-resolved-versions` is clean.
- **Docs:** `skills-and-mcp.md` now says that skill trust covers `SKILL.md`, not the files beside it.

## Checked and sound

- **TLS and endpoints.** `URLSessionTransport` is the one path for every provider, sign-in and MCP request: an ephemeral session, the
  system's TLS evaluation (no trust override anywhere in the code), redirects refused. `EndpointPolicy` allows a credential over https,
  or over plain http to loopback only; `ANTHROPIC_BASE_URL` goes through it. `providers.json` is read only from ask's config folder.
- **Project configuration.** `.ask/config.json` is used only after `ask trust`, by SHA-256. It cannot pass environment variables, set
  the shell, `approvals` or `credentials`, expand `${}` in MCP servers, or enable or enlarge skills. ask loads no `.env`.
- **Sign-in.** Loopback listeners on 127.0.0.1, `state` checked, PKCE, and the system's CSPRNG.
- **`ProviderProxy`.** Listens on 127.0.0.1, CONNECTs only to its allowlist, adds no credentials.
- **Skills.** `SkillContents.load` re-checks the trusted digest when it reads; `allowed-tools` grants nothing.
- **Session parser.** Archive and line size limits before parsing; image store names are 64 hex digits, and bytes are trusted only
  when they hash to their name.
- **Media.** ImageIO, PDFKit (CoreGraphics) and AVFoundation parse; ask caps a media file at 128 MiB, bounds pixels and bytes before
  sending, and guards a zero-page PDF and a non-finite duration.
- **Supply chain.** The Aemi family and TerminalKit are pinned by revision; argument-parser and subprocess allow patch releases only
  (`.upToNextMinor`), recorded in `Package.resolved`. swift-syntax 604.0.0 comes in through the macros of aemi and AemiJSON (the
  owner's): macro code runs on the build machine, so their pins matter. No plugins or binary targets. Workflow actions are pinned by
  SHA and the workflows declare `permissions`.

## Hardening notes, not fixed

- **Skill trust covers `SKILL.md` only.** A trusted skill's scripts and references can change after trust without a new prompt; ask
  does not run them itself, but the skill tells the model to. Proposed for the owner: digest the whole skill folder.
- **`ProviderProxy` starts a thread per connection, unbounded.** Only local processes reach it; informational.
- **The extension host is not built** (0033, items 2–5). When it is, it needs project trust before any extension of a repository
  loads, a sandbox of its own, and a defined behaviour when an extension crashes or hangs (the turn goes on without it).

## Measured after the fixes

The gate (`Scripts/quality.sh --check`) is clean. All seven probe suites pass on the hardened, signed release build (interactive with
the signed `/reload` section H4, picker, skill picker, connections, agent run, model accounts, model scopes). Budgets, at load 7–10: cold
start medians ranged from 32 to 90 ms for every build, `d1d8353` included, and the same binary signed without the hardened runtime
measured 54 ms against 46 ms with it, so the load decides those numbers and the runtime's cost is not measured. Idle memory is 16.1 MiB, against 16.0 for `d1d8353` built and measured
alongside, so the fixes cost about 0.1 MiB. Both are over the 15 MiB budget, as 0088 recorded on 10-30 (deferred by the owner).

## Not verified

- Signing now sets the hardened runtime. Re-signing changes the flags, not the designated requirement, so the owner's Keychain items
  should still open with no prompt. Not checked against the real items.
- Apple's on-device model (AskApple) under the hardened runtime: no probe exercises it.
- CI for this commit.
