# Engineering plan: architecture, reliability, resilience, security, testing, performance (2026-11)

2026-11-13. The owner asked for a study of the codebase and a schedule of improvements, to come before the heavier parts of the
roadmap. Everything below is measured on main (`8fd6df0b`) unless it says otherwise; it builds on the earlier work rather than
repeating it: the rationalisation pass (`rationalisation-2026-11.md`), the security audits of 2026-10-29 and 10-31, roadmap 0028
(quality gaps), 0183 (critical-software practices) and 0189 (the gate in Swift).

## 1. What the code is

| Module | Files | Lines | Test files | Test lines | Tests |
|---|---:|---:|---:|---:|---:|
| AskAI (providers, transport) | 268 | 12,919 | 160 | 15,378 | 995 |
| AskAgentCore (loop, sessions, context) | 381 | 19,836 | 221 | 16,848 | 1,120 |
| AskTUI (screen) | 246 | 15,496 | 212 | 18,155 | 1,174 |
| AskTools | 116 | 7,416 | 94 | 8,157 | 476 |
| AskMCP | 41 | 2,212 | 20 | 2,051 | 109 |
| AskApple, AskCore | 13 | 734 | 29 | 2,111 | 116 |
| **ask (the executable)** | **155** | **9,806** | **0** | **0** | **0** |

- The executable is the composition root and holds the conversation (`AgentConversation`: **46 extension files, 4,028 lines**),
  commands, sign-in flows, sessions switching, threads, goals, loops, forge reads. It has no test target, so the mutation run skips
  it (544 mutants never run), and its defects are found only by PTY probes. This week's lock-after-`/new` defect lived there.
- `ScreenController` is 44 extension files (3,227 lines); `AgentLoop` 15 (1,155). Each is one type spread over many files to stay
  under the 250-line limit: the limit is met, the type's size is not reduced.
- Concurrency: 50 `Mutex`es, 1 actor of ask's own, **110 unstructured `Task {}` or `Task.detached`** (ask 36, AskTools 34, AskTUI 17,
  AskMCP 11), 2 `@unchecked Sendable`, no `nonisolated(unsafe)`, 52 `unsafe` (strict memory safety in the kernels).
- Errors: **344 `try?`** (errors dropped): ask 73, AskAgentCore 101, AskAI 80, AskTools 51. Of those, 35 drop the error of a write,
  record, save or removal (ask 16, AskTools 9, Session 6, Search 2, Storage 2). No force unwrap, no `try!`, 3 preconditions.
- Processes: spawned only in `CommandCheck` and `JobWatchdog`; 43 `URLSession` uses.

## 2. What was found

### Reliability and resilience

1. **Untested composition root.** 9,806 lines in `Sources/ask` with no unit test; the mutation gate cannot see them (roadmap 0028 §2
   said so on 2026-10-19; still open).
2. **Unstructured tasks hold what they should not.** The `/new` defect (2026-11-13) was a `Task {}` that kept a session alive while it
   waited on a model. 110 such tasks exist; none is audited for what it captures, for cancellation when its owner goes, or for
   ordering against the work it races.
3. **Dropped errors where data is written.** 35 `try?` around writes: a session thread rename, a remembered encryption choice, reload
   grants, the search index, list conversions. A failed write is silent; the person learns at the next start, if at all.
4. **CI failures went unseen for ten days** (mutation, 2026-11-02 to 13). Fixed on 2026-11-13 (issues opened by failed scheduled runs,
   roadmap 0211); the same must hold for the nightly sweep's flaky list, which today is only said in its summary.
5. **Flaky under load.** Four probes fail when four run together and pass alone: something in them, or in ask, waits on time a busy
   machine does not give. Notes n18 and n55 (the screen blocked under load) are the same family.

### Security

6. **The last audit is two weeks and many features old.** Since 2026-10-31: MCP OAuth (and its renewal), session encryption and its
   keyring, the search index (sealed), `#123` (GitHub bodies into the context), the goal judge (reads the transcript), `/loop`, threads
   and subagents, openers (clicked links start apps), `!!` commands, the forge's token, the Copilot sign-in. Each is a new path for
   untrusted input (a web page, an issue body, a tool result, a model's reply) to reach a decision or a process.
7. **Prompt injection has no stated policy.** Issue bodies, MCP results and web pages enter the context as text; the goal judge can be
   told "MET" by text it reads. Note n33 asked for safeguards; the openers have confirmation, the rest has none written down.

### Testing

8. **No fuzzing.** The parsers that read untrusted bytes (SSE, JSON through AemiJSON, the session framing and its recovery, MCP
   messages, terminal input) are tested by examples only.
9. **Mutation baseline stale since 2026-10-31** (fixed in CI 2026-11-13; the first sharded run is Monday). After it, 38 known
   survivors in touched files wait.
10. **Probes are the only tests of the screen as a whole** and now run nightly; the 2 flaky ones per run are not yet triaged.

### Performance

11. **Memory over budget**, measured today (load does not change it): idle **19.3 MB against 15**, active **29.8 MB against 25**.
    Cold start (116 ms against 50) and action delay (12.2 against 8) were measured at a load average of 156 and need an unloaded
    machine (t14, t26).
12. Budgets are measured by script, not gated: an over-budget build lands.

## 3. The schedule

Five phases, each a set of roadmap entries, in order; each ends with a measured result. Estimates are working sessions.

### Phase A: see what fails (1 to 2 sessions)
- A1. The nightly sweep's FLAKY probes and the 4 found today: each made deterministic (waits on a condition, not a time) or its
  ask-side cause fixed. Done when 3 nightly sweeps in a row have none.
- A2. Commit the first sharded mutation baseline (t263); then kill or accept, with a reason each, the 38 survivors.
- A3. Budgets gated: `measure-budgets.py` runs nightly beside the sweep on the CI runner, its numbers recorded, an issue opened when
  one is over (the same mechanism as 0211). Local numbers on an unloaded machine for the record (t14).

### Phase B: the composition root becomes testable (3 to 5 sessions)
- B1. `AskSession`, a library target: `AgentConversation` and what it owns (commands, sessions, threads, goals, loops, forge, naming)
  moved out of the executable, behind the `ConversationUpdate` channel it already speaks. `Sources/ask` keeps `main`, argument
  parsing and the wiring. Then `AskSessionTests`, and the mutation run covers it.
- B2. The command registry (roadmap 0210, t243) lands here: one table, typed handlers, tested without a screen.
- B3. Tests for the session lifecycle the probes found: switching, `/new`, fork, resume, reload, each asserting the old session's
  lock is released at once.

### Phase C: resilience (2 to 3 sessions)
- C1. Every unstructured `Task` audited: what it captures (weakly when it outlives a session), who cancels it, what it races. Those
  that belong to a session become children of a per-session task group cancelled on switch; the rest named and documented.
  A test per lifecycle event that no task of the old session is left.
- C2. The 35 dropped write errors: each either surfaced (a notice, a retry) or justified in a comment; a rule in the gate that a new
  `try?` around a write needs one of the two.
- C3. Under load: a probe mode with an artificial CPU load (the budgets' `ASK_BUDGET_LOAD`) for the screen's input path (n18, n55),
  and the input loop's priority checked against it.

### Phase D: security (2 sessions)
- D1. Audit 3, threat model updated for the features since 2026-10-31 (list in §2.6), findings fixed test first, as audits 1 and 2.
- D2. A written prompt-injection policy (note n33): what untrusted text may cause without the person (nothing that runs, writes,
  opens or sends), how untrusted text is marked in the context (issue bodies, MCP and web results), and the goal judge told that the
  transcript may lie. Tests for each rule.
- D3. Roadmap 0183's research note (critical-software practices), with SBOM, reproducible and signed releases weighed.

### Phase E: testing depth and performance (2 to 3 sessions)
- E1. Fuzzing for the byte parsers (SSE, session framing and recovery, MCP framing, terminal input decoding), with Swift's
  libFuzzer support, in CI on a schedule; each crash a red test.
- E2. Memory back under budget: allocation traces of idle and active (what grew since the budgets were set: search, forge,
  catalogs, the git segment), then the fix, measured.
- E3. Cold start and action delay on an unloaded machine; regressions bisected by the nightly record.

## 4. Decisions for the owner

1. The order: A then B then C, D, E (proposed), or security (D) first.
2. B1: moving the conversation into a library target `AskSession` (the largest change here, mechanical but wide).
3. C2: a gate rule against new `try?` around writes without a reason, or review only.
4. A3: budgets checked nightly with an issue when over, or gated on every push (slower CI).

## The owner's answers (2026-11-13)

- Phase A is not a priority: B, C, D and E follow (roadmap 0229 to 0232).
- B (`AskSession`): yes. C: a gate rule against a new `try?` around a write without a reason.
- Budgets: on every release (0232, with roadmap 0070's release).
- From the study of other agents: file checkpoints (0233), machine-readable runs (0234), ACP (0235), diagnostics after edits (0236),
  web fetch (0237); the cheap ones (0234's JSON lines, 0237) come first, between the phases.
