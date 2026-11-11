# What the owner asked for, and what was proposed (2026-11-11, task t257)

White paper §7 bans building more than the owner asked. This note sorts every open task and every roadmap entry not done by where
it came from, using what each one records: the owner's note, idea or words, or nothing. It changes nothing; the owner decides what
stays. "Mine" means proposed by an agent, in a plan or a research pass, not asked.

## A. Asked by the owner, and still open

| Item | The ask | Open part |
|---|---|---|
| t195 | Status bar: the working path; what it shows and in what order (n6, n7, n63) | All |
| t196 | Chat with another running session (n8) | All |
| t197 | Over-linking in the family's binaries (n9, idea i9) | All |
| t202 | Drag the sidebar edge and the input's top rule (n12) | All |
| t205 | Threads part 2 (n15–n23) | One choice of the owner's: whether a thread's tasks carry its name |
| t206 | Nothing blocks the screen (n18) | Fixed and measured; the owner's kitty check |
| t209, t222, 0181 | Search over everything a session holds (n26), indexed during compaction (n42); light indexing (wish 2026-11-01) | Research |
| t212 | Leaving a job's lane on long sessions (n29); the owner added `ui.historyLimit` (2026-11-06) | The setting |
| t214, 0215 | Paths in replies (n31) | Real-terminal check |
| t215, 0216 | Openers (n32, n33) | Real-terminal check; steps 5 and 6 are mine (section C) |
| t216 | `/goal` and `/loop` (n34) | Research and a design |
| t227, t228 | Binary weight (n45), repinning the family (n46) | Follow-ups of the research |
| t232 | `jobs.keepFinished`, unlimited by default (owner, 2026-11-06) | All |
| t233 | `/reload` slow on big sessions (n47) | All |
| t236 | Scroll inertia blocks input (n50, n55) | Not reproduced; the owner's terminal |
| t237, t238, 0208 | Images in the conversation; pasting one (owner, 2026-11-06) | The rest of 0208 |
| t250 | Hover lights every copy of a link (n58) | Not reproduced |
| t258 | Idle title (n65) | Deferred by the owner: likely the terminal app |
| t10, 0115 | Take over another running session (owner's direction in 0115) | Research; the design in it is mine |
| t50, t51, 0140, 0190 | A dylib extension platform (n3, idea i3), a Swift edition (n2, idea i2); the owner answered 2026-11-02 | Blocked by 0192 and 0033 |
| t189, 0192 | Where hooks attach (owner, 2026-11-02, answering 0140) | Defaults are mine (section C) |
| t9, 0170 | The `/config` editor keeps comments (owner chose this, 2026-10-31) | All |
| t13, 0123 | AskMCP covers every MCP version and transport (owner, 2026-10-28) | The proposed shape is mine |
| t11, t12, t192, 0067, 0114 | MCP client and MCP for developing ask (the owner's choices, 2026-11-02) | Remaining gaps |
| t15, 0189 | The gate and tooling in Swift (owner wish and answers, 2026-11-01) | All |
| t32 | Markdown and Mermaid: 0065, 0066, 0151, 0152 (owner), 0178 table borders (wish 2026-11-01) | Each entry's rest |
| — | Mermaid and Markdown kits: 0196–0201, 0203–0205, 0207 (owner, 2026-11-04) | Each entry's rest |
| t33, 0032 | A background summary and compaction advisor: "the user's proposal, 2026-10-19, to be investigated, not built" | Investigation |
| t34, 0107 | A debug mode (owner wish, not a priority) | What it shows, with the owner |
| t36 (0155) | Setup allowances for common tools: owner said "later" (2026-10-30) | Later |
| t38 | Interop: 0146 Claude Code tools (owner request), 0150 tool middleware (owner wish), 0130 MDM (owner wish) | 0149's origin is not recorded |
| t39 | Aemi: 0109 AemiHMMML (n44), 0059 safe regex (owner asked) | 0076 is not recorded (section B) |
| t40 | 0121 event-driven (owner wish), 0122 protobuf (owner's condition) | Investigation |
| t41, 0135 | Linux, Windows, slimmer binaries (owner wish, 2026-10-29) | Investigation |
| t42 | 0070 a release (asks the owner first whether to ship a binary), 0071 real use with a defect log | Owner's answers |
| t44, 0073 | Xcode's code model in a chat (owner asked; "later") | Low priority |
| t47, t48 | `/rewind` as a tree, `/reload` builds: the owner marked them low priority | Low priority |
| t49 | Measure AemiRegex against Swift Regex: the roadmap asked for it | Measurement |
| 0074, 0078, 0187, 0179, 0180, 0182, 0194, 0195, 0110, 0139 | The owner's requests or ideas, each recorded in its entry | Each entry's rest |
| t16, t17, t19, t20, t22, t46 | The owner's own checks: real terminal, signing, keychain, screenshots | The owner's |

## B. Not recorded as asked: from the early plan, or found along the way

These have no owner's words in them. Some come from the first plan, some are maintenance or findings. The owner says whether each
stays.

| Item | What | Where it came from |
|---|---|---|
| t24, 0003 | Use the terminal probe instead of guessing | Early plan |
| t25, 0014, 0015 | Measure cell pixels and chrome cost; compact pixel layouts | Early plan (0015 holds owner's decisions on a prototype) |
| t27, 0034, 0038, 0040, 0046, 0047 | Provider presets, catalogs, Responses reasoning, named connections | Early plan; 0046 and 0047 hold proposed commands |
| t28, 0052, 0055, 0069 | Antigravity connector, Gemini 3 signatures, the probe | Early plan; several owner's decisions pending in them |
| t29, 0053 | Thinking levels: finish | Split out of 0043 |
| t31 | Screen leftovers: 0048 grammar, 0051 interaction model, 0074, 0078 | 0051 and 0074 hold the owner's wants; the leftovers listed are mine |
| t36 (0020, 0022) | Run ask sandboxed; container isolation | Early plan |
| t37 (0033, 0012) | The extension host (ADR-0028); codemode | Early plan |
| t39 (0076) | Algorithms owned by Aemi subpackages | A rule; not recorded whose |
| t43 (0028, 0183) | Close the audit's gaps (mine); critical-software practices (owner wish 2026-11-01) | Mixed |
| t14, t26, 0054 | Budgets over limit, cold-start variance | The budgets' own checks |
| t21 | Verify CI and the Linux legs | Process |
| t186 | TerminalKit writes a single underline as `4:1` | A finding of a probe |
| t230 | A fake Codex address for probes | A finding (a probe spent a real token) |
| t246 | Move the land and sweep scripts out of `/tmp` | A finding (they were lost) |
| 0186, t5 | Git integration and `#` references | Early plan |
| 0202, 0206 | A zero-copy fence reader; Markdown rows without string churn | Mine, in service of the owner's Markdown asks |

## C. Proposals waiting for the owner inside asked items

Not to be built until the owner says so.

| Where | The proposal |
|---|---|
| 0216 | Step 5, `/config resolveOpeners`; step 6, presets (a draft of step 5 is not committed) |
| 0209–0212, t242–t245 | One declaration per setting; one registry of slash commands; the PTY sweep in CI; roadmap hygiene. The rationalisation pass the owner asked for (n53) proposed them; the owner answered 0209's §5.1 and chose two parts of 0212 on 2026-11-08 |
| 0195 | The lifecycle, what is recorded, the settings, and "what the owner had not asked about" |
| 0051 | The parts marked proposed, "to be accepted, changed or refused" |
| 0046, 0047 | The proposed commands and selection |
| 0123 | The proposed shape per server |
| 0186 | The proposed order (`#t3` and `#i2` first) |
| 0192 | The proposed timeouts (5 s, 1 s) |
| 0115 | The design (two processes per session, a socket) |
| t205 | Whether a thread's tasks carry its name |
| t257 | This note |
