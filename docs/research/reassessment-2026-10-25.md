# Reassessment, 2026-10-25: where `ask` stands and what to do next

A snapshot, not a plan of record: the plan is `docs/roadmap/`, the decisions are the ADRs, and this note is the reading of both against what was measured today. It
exists because nobody had stepped back since the first week. It follows the evidence rule: a statement that was probed says so and names the command; one that was only
read says "read"; one that is a judgment says "judgment". What it did **not** look at is listed at the end.

## 1. How it was made

| Measured or probed | How |
|---|---|
| Size and tests per target | `wc -l` over `Sources/*` and `Tests/*`; `@Test` counts; the last full gate (2,086 tests) |
| Roadmap state | every entry's `status:` and its "still owed" section, extracted by script; 32 done, 22 in progress, 13 not started (before the five entries this note adds) |
| History | `git log` (410 commits, 2026-10-18 to 2026-10-25), `--grep=renumber`, worktrees |
| Whether commands inherit ask's secrets | `Scripts/probe-bash-environment.py`, a fake Anthropic server and a stand-in key |
| Whether ask has a version | `ask --version` (an unknown option) |
| Whether real use is recorded | `rg -i dogfood docs` before the entry that names it (no hits) |
| The budgets under load | six interleaved pairs of `Scripts/measure-budgets.py`, 12 runs each, at load 8 to 15 |
| The Antigravity connector | the live runs and probes of the last two days; see `antigravity-2026-10.md` |

## 2. The project today

**What exists and works** (each line was exercised by a test, a probe or a live run; the evidence is in the ADRs and diaries):

- **Providers.** Claude (a subscription or a key), Codex (the ChatGPT subscription, Responses protocol, reasoning replay), Antigravity (Cloud Code, Gemini 3, Claude and GPT-OSS
  models), and any OpenAI-compatible or Responses server by configuration or preset, with catalogs, aliases, thinking levels and named connections for the subscriptions.
- **The loop.** Tool calls, retry with backoff (`RetryPolicy`), compaction, a usage limit that is not retried, a rotated sign-in kept in memory when its save fails and announced once.
- **Tools and safety.** `read`, `write`, `edit`, `bash` and background jobs under a default Seatbelt sandbox (secret stores and ask's own files off limits), a model that may narrow but not widen
  its own sandbox, a watchdog that stops jobs when ask is killed.
- **The screen.** Folding, selection, mouse, a command and a file picker, multi-line input, `/tree` and `/fork`, Markdown, and now Antigravity.
- **Reliability work.** Sessions recovered and never rewritten on read, atomic stores, a model of the credential and session protocols, fault injection of the file operations.
- **Process.** A gate (`Scripts/quality.sh`), three analyzers (deadwood, dolly, arcleak), mutation testing of new rules, an evidence rule that has overturned beliefs repeatedly.

**Size** (`wc -l`, today): `AskAI` 9,325 lines, `AskAgentCore` 7,028, `AskTUI` 3,551, **`ask` 3,301**, `AskTools` 3,037, `AskMCP` 1,269, `AskCore` 85 (27,596 in all) against about 29,750
lines of tests: **2,086 tests**, none of them in `ask`.

**Budgets** (`ask --budgets`: cold start 25 ms, idle memory 24 MiB, input delay 2 ms, action-to-action 5 ms), measured today, six interleaved pairs, load 8 to 15:

| | Range of the medians | Budget | Reading |
|---|---|---|---|
| Cold start | 13.1 to 25.1 ms | 25 | passes when the machine is quiet; **over it by 0.1 ms in one loaded round** |
| Idle memory | 9.17 to 9.28 MiB (9,392 to 9,504 KiB) | 24 | large margin; +56 KiB for the last feature measured |
| Input delay | 0.23 to 0.53 ms | 2 | large margin |
| Action-to-action | 2.2 to 4.9 ms | 5 | passes quiet; **0.1 ms from the limit at load 15** |

The loaded figures swing by a factor of two with nothing changed, so the budget run cannot say whether a change regressed cold start or action delay unless the machine is quiet. That is roadmap
0054 and an owner decision (below).

## 3. What is left

| Theme | Open work (roadmap) | Waits for |
|---|---|---|
| **Providers** | Antigravity's unknowns (0069, `antigravity-2026-10.md`); presets that need keys (0034, 0038, 0055); Responses replay on direct OpenAI (0040); a named Antigravity connection (0052, 0046) | the owner's keys, a second account, approval of one large request |
| **Context** | a background summary and a compaction advisor (0032, not started); whether compaction works well in long real sessions (nobody knows: 0071) | real use |
| **Safety** | commands inherit ask's environment (**0072, new**); ask itself unsandboxed (0020); network by domain (0021); a container (0022, research) | nothing for 0072; the rest are large |
| **Extension routes** | MCP (0067), skills (0061), subagents (0063), the extension host (0033), codemode (0012): **five routes, three of them overlapping, one decision missing** (see finding 7) | an owner decision |
| **The screen** | keys (0064), the runner tree (0062), Markdown and Mermaid (0065, 0066), interaction and input (0048, 0049, 0051), two layouts (0015) | in flight by another agent; 0064 changes what Esc does |
| **Quality** | tests for the composition root (0028); CI has never run; analyzer debt (0025, 0016) | CI needs the owner's billing |
| **Performance** | budget verification under load (0054); idle memory trend | an owner decision |
| **Distribution** | no version, no release, no install path (**0070, new**) | the owner: is ask to be distributed? |
| **Process** | record-number collisions (**0068, new**) | nothing |
| **Aemi** | a safe regex and a kernel (0059) | the owner's five decisions in `aemiregex-requirements-2026-10.md` |

## 4. What the reassessment found

Each finding has its class. Numbers 1 to 5 are new; 6 to 10 were known and are put in order.

1. **A command the model runs can read ask's secrets from the environment, and the value goes to the provider.** *Probed.* `Scripts/probe-bash-environment.py` sets a stand-in
   `ANTHROPIC_API_KEY` and another token, has a fake model run `echo` on them, and finds both in the tool result sent in the second request. The sandbox protects secret *files*
   (`~/.config/ask`, `~/.aws`, Keychains) by default, and a provider key a person exports lives in the environment. This is a security exposure the project created by being inconsistent,
   it has been in roadmap 0028 item 13 since 2026-10-19 with "decide whether to scrub it", and it was never decided. **Roadmap 0072.**
2. **`Sources/ask` is 3,301 lines with no tests.** *Measured.* 11% of the source, and the place every new provider, command and cache lands. This session needed a temporary print of the
   resolved window to check one 10-line function. Live runs cover the paths a person takes; nothing covers the paths a person does not. Roadmap 0028 item 2, now with numbers.
3. **Record numbers collide, and git cannot see it.** *Measured.* 17 of 410 commits are renumberings (12 since 2026-10-23); two ADR 0095s and two diary 06s existed on different branches with different
   file names, so no merge conflict reported them. Four worktrees are open today. **Roadmap 0068.**
4. **ask has no version.** *Probed.* `ask --version` is an error; the Antigravity identity says `ask/0` for lack of anything better; the README says "build from source". Nothing a
   second user needs exists. **Roadmap 0070.**
5. **No sustained real use is recorded.** *Searched.* 410 commits, 102 ADRs and 138 diary files, and no file describes using ask for a task of an hour. The live runs of the last week were single
   tool calls. The context, retry and compaction designs have never had real data, and the roadmap is ordered by what is interesting to build. **Roadmap 0071.**
6. **CI has never run.** *Read, repeatedly:* GitHub refuses to start the jobs for a billing reason, since 2026-10-19. The gate is a script that every agent runs by hand, which is why 0068 matters.
7. **Five extension routes, no decision about how they relate.** *Read.* ADR-0028 says third-party code is an extension process speaking JSON-RPC (0033: tools **and hooks**); MCP (0067, in progress with a working
   client) is also tools from another process and shares its transport; skills (0061) are prompt-level; codemode (0012) is a script that composes tools; subagents (0063) compose agents.
   0067 does not mention 0033 or 0012. Whether 0033's tool half is now MCP, and what remains of it (hooks), is a question an ADR answers in an afternoon and that five entries wait on.
8. **Owner-gated items are accumulating, and some are old.** *Read.* CI billing (since 10-19); the budget-verification decision for 0054 (10-22); the account chooser (0046, 10-20); a Gemini key (0055);
   the five AemiRegex decisions (0059); the first-party identity and the terms question for Antigravity (0052, U12 and U22). None is blocking, and together they are a list of things the project
   cannot learn without the owner.
9. **The budgets cannot be certified on this machine under load.** *Measured today.* See the table in section 2.
10. **Documents had drifted.** *Read.* `AGENTS.md` ("Current state") and the README ("Status") both said a second provider was not built, three had been; roadmap 0052 listed finished work as owed and an
    undecided question that ADR-0090 had decided. Corrected in this change. The interactive probe for Antigravity relies on Esc aborting, which 0064 (the owner's direction) removes; the probe will
    need to follow.

## 5. The most valuable next iterations, in order

The ordering is judgment applied to the evidence above: a defect that exposes a person first, then what makes every later iteration cheaper, then what produces information the roadmap
lacks, then what closes a known risk, then what a second user needs.

| # | Iteration | Why it ranks here | Cost | It is done when | Needs |
|---|---|---|---|---|---|
| **1** | **0072 — commands do not inherit ask's secrets** | The only exposure found; reproduced; the default is cheap to choose (deny the variables ask itself reads credentials from) and the allow-list option can be measured first | Small: an ADR, one scrub where a tool process is started, a test per rule | `Scripts/probe-bash-environment.py` exits 0 and a configured pass-through works | the ADR's default (the owner can veto) |
| **2** | **0068 — land a change with one command** | The cost is paid by every agent on every landing; atomic claims through shared refs are a small, probe-able idea; it makes everything after it cheaper | Small | eight concurrent claimants get eight numbers; a duplicate-number tree is refused | nothing |
| **3** | **0071 — use ask for real work** (start now, run alongside the rest) | The only way to learn what the roadmap does not know; it can change every ranking below; the numbers it yields (tokens, compactions, refusals, time) are the ones the context and retry designs lack | Quota and hours, not code | five sessions of an hour with a defect log, sorted | the owner's daily use is best |
| **4** | **0028, item 2 — a testable composition root**, first slice: resolve a model and its limits from a cache (the function that needed a print statement) | 3,301 lines untested, and the area that changes most; a first slice proves the shape before the rest moves | Medium; slice it by behaviour | the first behaviours have tests with a fault each; `Sources/ask` shrinks by what moved | nothing |
| **5** | **0069 — Antigravity: probe where ask only guesses** (steps 1 to 4 now; step 5 after approval) | Closes the connector's known risks cheaply; the length refusal decides whether compaction works on a provider whose recognizer is a guess | Small for 1 to 4; one large request for 5 | each unknown has a verdict and a fixture | the owner for step 5 |
| **6** | **0070, first half — a version** (`ask --version`, the identity strings, the session record) | Independent of whether ask is ever distributed; it removes the `ask/0` placeholder and makes a bug report possible | Small | `ask --version` prints it and every provider's `user-agent` carries it | an ADR on the scheme |
| **7** | **An ADR: how MCP, the extension host, skills and codemode relate** | Five roadmap entries wait on one question; it may close two of them | An afternoon | 0033 and 0012 are narrowed, superseded or confirmed, in writing | the owner |
| **8** | **The owner's batch** (section 6) | Each unblocks something; none is urgent; together they are the project's open loops | The owner's time | answered in writing, each in an ADR or an entry | the owner |

**Why not the screen features, subagents, Mermaid, codemode or a container?** The screen is in the hands of another agent and is the most-built part of the project; nothing found today argues
for more of it before real use (item 3) says what hurts. Subagents and the runner tree (0062, 0063) are large, depend on 0064 and 0061, and are "off by default" by decision. Codemode (0012) waits on 0014's
measurement and, since MCP and skills exist, on the ADR of item 7. A container (0022) and ask-in-a-sandbox (0020) are bigger versions of item 1's problem: do the small one first and see whether the large ones
are still wanted. AemiRegex (0059) has one runtime use in three short error messages and waits on its owner decisions. A background summary (0032) waits on data that item 3 produces.

**What would change this order.** A real session that loses work or fails in a way item 3 finds would outrank everything but item 1. A decision by the owner not to distribute ask lowers 0070 to its first half. A
second user lifts 0070 and CI to the top. Approval for the large Antigravity request moves step 5 of item 5 up the same day.

## 6. Decisions only the owner can make

1. **0072's default**: deny the variables ask reads credentials from (recommended), or allow only a short list (safer, breaks `gh`, `aws`, `npm` unless configured).
2. **Is ask to be distributed**, and if so with a signed binary or from source (0070)?
3. **CI**: the GitHub billing problem, or an agreed substitute (the landing script of 0068 is one).
4. **Budget verification under load** (0054): report the efficiency-core share beside the median, require it low, or leave the budget as it is.
5. **The Antigravity questions** (`antigravity-2026-10.md`): approval of one request of about 140,000 tokens (U1); whether the first-party identity may be sent once to measure the catalog (U12); whether the
   `tab_*` and image models may be chosen (U19); and whether the subscription's terms allow this use (U22, which no probe settles).
6. **The extension routes** (item 7): which of 0033, 0012 and 0067 is the way third-party tools arrive.
7. **The five AemiRegex decisions** of `aemiregex-requirements-2026-10.md`.
8. **Keys and accounts**: a Gemini API key (0055), a second Google or ChatGPT account (0046, U21).

## 7. What this reassessment did not do

- It did not **review the screen, MCP, skills or Markdown**: their status is read from their entries, and nothing was run against them beyond the Antigravity runs.
- It did not **run every probe script** or the full mutation suites; "green" means the last gate (2,086 tests) and the probes named above.
- It did not **audit the sandbox** against an adversary: finding 1 came from a single probe of one channel (the environment), and other channels (the network, which is open by default, and any secret the policy does
  not name) were not tried.
- It did not measure **what the budgets cost on a quiet machine today**; the numbers in section 2 were taken at load 8 to 15.
- The ranking is a judgment. The evidence behind each row is stated so that the owner can disagree with the weights and not with the facts.
